// Kill Cord Teams waitlist: adds a signup to Kit with the killcord-teams-waitlist tag and kc_* fields.
// Stays closed (503) until KIT_API_KEY and KIT_TEAMS_FORM_ID are set in Vercel. See site/README.md.
// Kit API v4: https://developers.kit.com/api-reference/subscribers/create-a-subscriber

const KIT = 'https://api.kit.com/v4';
const DEFAULT_TAG_ID = '26383705';
const SIZES = new Set(['1', '2-10', '11-50', '51+']);
const PROVIDERS = new Set([
  'anthropic', 'openai', 'google', 'vercel', 'cloudflare', 'twilio', 'neon', 'supabase', 'openrouter', 'other',
]);
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

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
    fields: {
      kc_company_size: size,
      kc_providers: [...new Set(providers)].join(', '),
      kc_ref: /^[a-z0-9-]+$/.test(ref) ? ref : '',
      kc_must_have: clean(body.must_have, 1000),
    },
  };
}

async function kit(path, key, payload) {
  const response = await fetch(KIT + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Kit-Api-Key': key },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(`Kit ${path} answered ${response.status}`);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Use POST.' });
  }
  const key = process.env.KIT_API_KEY;
  const formId = process.env.KIT_TEAMS_FORM_ID;
  const tagId = process.env.KIT_TEAMS_TAG_ID || DEFAULT_TAG_ID;
  if (!key || !formId) return res.status(503).json({ error: 'The waitlist isn’t open yet.' });

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  // Bots fill the hidden field; people never see it.
  if (clean(body.website, 200)) return res.status(200).json({ ok: true });
  const signup = parse(body);
  if (signup.error) return res.status(400).json({ error: signup.error });

  try {
    await kit('/subscribers', key, { email_address: signup.email, fields: signup.fields });
    await kit(`/forms/${encodeURIComponent(formId)}/subscribers`, key,
      { email_address: signup.email, referrer: 'https://killcord.app/teams/' });
    await kit(`/tags/${encodeURIComponent(tagId)}/subscribers`, key, { email_address: signup.email });
  } catch (error) {
    console.error('teams-waitlist:', error.message);
    return res.status(502).json({ error: 'Something went wrong on our side. Try again in a minute.' });
  }
  return res.status(200).json({ ok: true });
};

module.exports.parse = parse;
