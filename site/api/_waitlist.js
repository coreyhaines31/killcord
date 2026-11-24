// Shared by the Teams waitlist functions. Files starting with _ are not routes on Vercel.
// No dependencies: Postgres over Neon's HTTP endpoint, email over PostShiba's HTTP inject.

const crypto = require('crypto');

const INJECT_URL = 'https://inject.postshiba.com/api/inject/v1';
const FROM = 'corey@mail.killcord.app';

// Replies go to WAITLIST_REPLY_TO when it's a plain address, so the real inbox stays out of the public repo.
function replyTo() {
  const address = (process.env.WAITLIST_REPLY_TO || '').trim();
  return /^[^\s@<>,]+@[^\s@<>,]+\.[^\s@<>,]+$/.test(address) ? address : FROM;
}

function configured() {
  return Boolean(process.env.WAITLIST_DATABASE_URL && process.env.WAITLIST_HMAC_KEY);
}

// Same wire format as @neondatabase/serverless: POST {query, params} to https://api.<host>/sql.
async function sql(query, params = []) {
  const url = process.env.WAITLIST_DATABASE_URL;
  const host = new URL(url).hostname.replace(/^[^.]+\./, 'api.');
  const response = await fetch(`https://${host}/sql`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Neon-Connection-String': url },
    body: JSON.stringify({ query, params }),
  });
  if (!response.ok) {
    const detail = await response.json().catch(() => ({}));
    throw new Error(`database answered ${response.status}${detail.code ? ` (${detail.code})` : ''}`);
  }
  return (await response.json()).rows;
}

function hmac(value) {
  return crypto.createHmac('sha256', process.env.WAITLIST_HMAC_KEY).update(value).digest('base64url');
}

function unsubscribeToken(id) {
  return `${id}.${hmac(`unsubscribe:${id}`)}`;
}

// Returns the signup id for a valid token, or null.
function readUnsubscribeToken(token) {
  if (typeof token !== 'string') return null;
  const [id, signature] = token.split('.');
  if (!/^[0-9a-f-]{36}$/.test(id || '') || !signature) return null;
  const expected = Buffer.from(hmac(`unsubscribe:${id}`));
  const given = Buffer.from(signature);
  return given.length === expected.length && crypto.timingSafeEqual(given, expected) ? id : null;
}

function siteUrl() {
  if (process.env.VERCEL_ENV === 'production') return 'https://killcord.app';
  return process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:4719';
}

function welcomeText(unsubscribeUrl) {
  return `You're on the list.

Kill Cord Teams gives your company one total for every API it pays for, shows who spent it, and keeps sending alerts while every Mac is asleep. I'm opening it to a small group of companies first, starting with this list. If yours is one of the first 100, your first 3 months of Team are at the Solo price.

One question, so I build the right parts first:

Roughly what's your company's monthly API spend, and which providers?

Just reply to this email.

Corey Haines
Kill Cord

--
You're getting this because you joined the Kill Cord Teams waitlist at killcord.app/teams.
Unsubscribe: ${unsubscribeUrl}
`;
}

async function sendWelcome(email, id) {
  const auth = process.env.POSTSHIBA_INJECT_AUTH;
  if (!auth) throw new Error('POSTSHIBA_INJECT_AUTH is not set');
  const unsubscribeUrl = `${siteUrl()}/api/teams-waitlist-unsubscribe/?token=${unsubscribeToken(id)}`;
  const response = await fetch(INJECT_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Basic ${Buffer.from(auth).toString('base64')}`,
    },
    body: JSON.stringify({
      envelope_sender: FROM,
      recipients: [{ email }],
      content: {
        text_body: welcomeText(unsubscribeUrl),
        headers: {
          From: `Corey Haines <${FROM}>`,
          To: email,
          'Reply-To': replyTo(),
          Subject: 'You’re on the Kill Cord Teams list',
          'List-Unsubscribe': `<${unsubscribeUrl}>`,
          'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
          'X-Capsule-Unique-Args': JSON.stringify({ kind: 'teams-waitlist-welcome' }),
        },
      },
    }),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok || result.success_count !== 1) {
    throw new Error(`PostShiba answered ${response.status}`);
  }
}

module.exports = { configured, sql, hmac, unsubscribeToken, readUnsubscribeToken, sendWelcome, welcomeText };
