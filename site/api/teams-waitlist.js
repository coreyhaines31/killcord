// Kill Cord Teams waitlist: stores a signup in Postgres (site.teams_waitlist) and sends one
// welcome email through PostShiba. Answers 503 until WAITLIST_DATABASE_URL and
// WAITLIST_HMAC_KEY are set in Vercel. See site/README.md.

const waitlist = require('./_waitlist');

const SIZES = new Set(['1', '2-10', '11-50', '51+']);
const PROVIDERS = new Set([
  'anthropic', 'openai', 'google', 'vercel', 'cloudflare', 'twilio', 'neon', 'supabase', 'openrouter', 'other',
]);
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PER_IP_PER_HOUR = 5;

function clean(value, max) {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max) : '';
}

function parse(body) {
  const email = clean(body.email, 254).toLowerCase();
  if (!EMAIL.test(email)) return { error: 'Enter a valid work email.' };
  const size = clean(body.company_size, 8);
  if (!SIZES.has(size)) return { error: 'Choose a company size.' };
  const providers = (Array.isArray(body.providers) ? body.providers : [])
    .filter((p) => typeof p === 'string' && PROVIDERS.has(p));
  const ref = clean(body.ref, 64).toLowerCase();
  return {
    email,
    company_size: size,
    providers: [...new Set(providers)],
    ref: /^[a-z0-9-]+$/.test(ref) ? ref : '',
    must_have: clean(body.must_have, 1000),
  };
}

function clientIp(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || String(req.headers['x-real-ip'] || '');
}

// A repeat signup updates the answers (keeping the first ref) unless the row changed in the
// last minute; then nothing is returned and the caller answers 429.
const UPSERT = `
  INSERT INTO site.teams_waitlist (email, company_size, providers, ref, must_have, user_agent, ip_hash)
  VALUES ($1, $2, $3, $4, $5, $6, $7)
  ON CONFLICT (email) DO UPDATE SET
    company_size = EXCLUDED.company_size,
    providers = EXCLUDED.providers,
    ref = CASE WHEN site.teams_waitlist.ref = '' THEN EXCLUDED.ref ELSE site.teams_waitlist.ref END,
    must_have = EXCLUDED.must_have,
    user_agent = EXCLUDED.user_agent,
    ip_hash = EXCLUDED.ip_hash,
    updated_at = now(),
    unsubscribed_at = NULL
  WHERE site.teams_waitlist.updated_at < now() - interval '1 minute'
  RETURNING id, welcomed_at IS NULL AS needs_welcome`;

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Use POST.' });
  }
  if (!waitlist.configured()) return res.status(503).json({ error: 'The waitlist isn’t open yet.' });

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  // Bots fill the hidden field; people never see it.
  if (clean(body.website, 200)) return res.status(200).json({ ok: true });
  const signup = parse(body);
  if (signup.error) return res.status(400).json({ error: signup.error });

  const ipHash = waitlist.hmac(`ip:${clientIp(req)}`).slice(0, 32);
  let row;
  try {
    const [recent] = await waitlist.sql(
      `SELECT count(*)::int AS n FROM site.teams_waitlist
       WHERE ip_hash = $1 AND updated_at > now() - interval '1 hour'`, [ipHash]);
    if (recent.n >= PER_IP_PER_HOUR) {
      return res.status(429).json({ error: 'Too many signups from this network. Try again in an hour.' });
    }
    [row] = await waitlist.sql(UPSERT, [
      signup.email, signup.company_size, signup.providers, signup.ref, signup.must_have,
      clean(req.headers['user-agent'], 200), ipHash,
    ]);
  } catch (error) {
    console.error('teams-waitlist:', error.message);
    return res.status(502).json({ error: 'Something went wrong on our side. Try again in a minute.' });
  }
  if (!row) return res.status(429).json({ error: 'You’re already on the list. To change your answers, try again in a minute.' });

  // The signup is saved either way; a failed welcome is retried on the next signup with this email.
  if (row.needs_welcome) {
    try {
      await waitlist.sendWelcome(signup.email, row.id);
      await waitlist.sql('UPDATE site.teams_waitlist SET welcomed_at = now() WHERE id = $1', [row.id]);
    } catch (error) {
      console.error('teams-waitlist welcome:', error.message);
    }
  }
  return res.status(200).json({ ok: true });
};

module.exports.parse = parse;
