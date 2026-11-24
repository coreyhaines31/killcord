// Unsubscribe from the Teams waitlist emails. The link in each email carries a signed token.
// GET shows a confirm button (link scanners open GET links), POST unsubscribes. Mail apps'
// one-click unsubscribe (List-Unsubscribe-Post) also POSTs here.

const waitlist = require('./_waitlist');

function page(res, status, title, body) {
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('X-Robots-Tag', 'noindex');
  return res.status(status).send(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} | Kill Cord</title>
<style>body{margin:0;background:#0d0d0e;color:#e8e8ea;font:17px/1.5 -apple-system,system-ui,sans-serif}
main{max-width:30rem;margin:15vh auto;padding:0 16px}h1{font-size:1.5rem;margin:0 0 .5rem}
a{color:#e8e8ea}button{font:inherit;padding:.6rem 1.1rem;border-radius:8px;border:1px solid #555;background:#1c1c1f;color:#e8e8ea;cursor:pointer}</style>
</head><body><main><h1>${title}</h1>${body}</main></body></html>`);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).send('Use GET or POST.');
  }
  if (!waitlist.configured()) return page(res, 503, 'Not available', '<p>Try again later.</p>');
  const token = String((req.query && req.query.token) || '');
  const id = waitlist.readUnsubscribeToken(token);
  if (!id) return page(res, 400, 'That link doesn’t work', '<p>The unsubscribe link is incomplete. Copy the whole link from the email, or reply to the email and we’ll take you off the list.</p>');

  if (req.method === 'GET') {
    return page(res, 200, 'Unsubscribe from Kill Cord Teams emails?',
      `<p>You’ll stop getting emails about the Teams waitlist.</p>
<form method="post" action="/api/teams-waitlist-unsubscribe/?token=${encodeURIComponent(token)}"><button type="submit">Unsubscribe</button></form>`);
  }

  try {
    await waitlist.sql(
      'UPDATE site.teams_waitlist SET unsubscribed_at = coalesce(unsubscribed_at, now()) WHERE id = $1', [id]);
  } catch (error) {
    console.error('teams-waitlist-unsubscribe:', error.message);
    return page(res, 502, 'Something went wrong', '<p>Try the link again in a minute.</p>');
  }
  return page(res, 200, 'You’re unsubscribed',
    '<p>You won’t get more Kill Cord Teams emails. Changed your mind? <a href="/teams/">Join again</a>.</p>');
};
