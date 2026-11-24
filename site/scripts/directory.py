"""The /track/ directory: one page per service from data/services.json, plus hubs. Only records with
"publish": true get pages, and hubs link only to those."""
from html import escape
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parent.parent
site = 'https://killcord.app/'
services = json.loads((root / 'data/services.json').read_text())
published = [s for s in services if s['publish']]
by_slug = {s['slug']: s for s in services}

categories = {
    'llm': ('ai-models', 'AI model APIs', 'LLM and model APIs that bill per token or per request.'),
    'ai-media': ('ai-media', 'AI voice, image and video APIs', 'Speech, image and video APIs that bill per character, credit or second.'),
    'infra': ('cloud', 'Cloud and hosting', 'Clouds, hosting and databases that bill for what you use.'),
    'email': ('email-messaging', 'Email and messaging APIs', 'Email, SMS and voice APIs that bill per message or from a monthly quota.'),
    'seo-data': ('seo-data', 'SEO data APIs', 'Keyword, backlink and SERP APIs that spend units or a prepaid deposit.'),
    'sales-data': ('sales-data', 'Sales data APIs', 'Prospecting and enrichment APIs that spend monthly credits.'),
    'scraping': ('scraping', 'Scraping and browser APIs', 'Scraping, crawling and screenshot APIs that spend credits or requests.'),
    'devtools': ('developer-tools', 'Developer tools', 'Developer platforms with metered usage on top of a plan.'),
}

# What the app shows for each built-in, matching ProviderInfo.capability in KillCordCore.
builtin_shows = {
    'anthropic': 'today’s and this month’s spend in dollars',
    'openai': 'today’s and this month’s spend in dollars, and whether the organization hard limit is on',
    'google-cloud': 'spend in dollars from your Cloud Billing export, after a one-time BigQuery setup',
    'vercel': 'today’s and this month’s billing charges in dollars',
    'cloudflare': 'this billing period’s spend in dollars, and whether a Spend Management limit is set',
    'twilio': 'today’s and this month’s spend in dollars, and whether a usage trigger is set',
    'neon': 'this month’s usage in compute hours, storage and transfer (Neon doesn’t report dollars)',
    'openrouter': 'the credit left on your key and that key’s spend today and this month',
    'dataforseo': 'the dollars left on your prepaid balance',
    'ahrefs': 'the API units your workspace has left this period, and when they reset',
    'firecrawl': 'the credits your team has left, and when the billing period ends',
    'treg': 'your team’s prepaid balance in dollars',
    'monid': 'your wallet balance',
}
# Built-ins with no native cap in Kill Cord's caps audit: a prepaid balance stops at zero on its own.
no_caps_audit = {'dataforseo', 'ahrefs', 'firecrawl', 'treg'}
caps_only = {'supabase'}
builtin_names = ('Anthropic, Google Cloud and Gemini, OpenAI, Vercel, Cloudflare, Twilio, Neon, OpenRouter, '
                 'DataForSEO, Ahrefs, Firecrawl, treg, and Monid')

kind_labels = {'hard-stop': ('stop', 'Hard stop'), 'partial-stop': ('part', 'Partial stop'),
               'alert-only': ('alert', 'Alert only'), 'auto-recharge-off': ('part', 'Top-up control')}


def e(text):
    return escape(text, quote=True)


def known(value):
    return value not in (None, '', 'unknown')


def inline(text):
    """Escape, then turn `backticks` into code and [text](url) into links."""
    html = re.sub(r'`([^`]+)`', r'<code>\1</code>', e(text))
    return re.sub(r'\[([^\]]+)\]\(([^)\s]+)\)', r'<a href="\2">\1</a>', html)


def sentence(text):
    text = text.strip()
    return text if text.endswith(('.', ')', '?')) else text + '.'


def cap_first(text):
    return text[:1].upper() + text[1:]


def lower_first(text):
    return text[:1].lower() + text[1:] if text[1:2].islower() else text


def noun(s):
    """What people check for this service: a balance, credits, or spend."""
    if s.get('noun'):
        return s['noun']
    t, units = s['billing_type'], s['spend_api']['units']
    if t == 'prepaid':
        return 'balance'
    if t == 'quota':
        return 'credits' if units == 'credits' else 'usage'
    return 'spend'


def title_for(s):
    if s.get('page', {}).get('title'):
        return s['page']['title']
    n = s['search_name']
    thing = {'balance': 'Balance', 'credits': 'Credits', 'usage': 'Usage', 'spend': 'Usage and Spend'}[noun(s)]
    for title in (f'How to Check Your {n} {thing} | Kill Cord', f'Check Your {n} {thing} | Kill Cord',
                  f'Check Your {n} {thing}'):
        if len(title) <= 60:
            return title
    return f'{n} {thing}'[:60]


def h1_for(s):
    return s.get('page', {}).get('h1') or f'How to check your {s["search_name"]} {noun(s)}'


def path_for(s):
    return f'track/{s["slug"]}/index.html'


def url_for(s):
    return f'/track/{s["slug"]}/'


def category_url(key):
    return f'/track/{categories[key][0]}/'


def tier_badge(s):
    tier = s['killcord']['tier']
    if s['slug'] in caps_only:
        return '<p class="bx-badge tier-on"><i aria-hidden="true"></i>In Kill Cord’s caps audit</p>'
    if tier == 'built-in':
        return '<p class="bx-badge tier-on"><i aria-hidden="true"></i>Built into Kill Cord</p>'
    if tier == 'planned':
        return '<p class="bx-badge tier-planned"><i aria-hidden="true"></i>Not in Kill Cord yet</p>'
    if tier == 'manual':
        return '<p class="bx-badge tier-on"><i aria-hidden="true"></i>Tracked by Kill Cord as a manual entry</p>'
    return '<p class="bx-badge tier-off"><i aria-hidden="true"></i>Not tracked by Kill Cord</p>'


def answer(s):
    """The one-paragraph answer to "can you read it from the API?", as plain text for the FAQ and HTML for the box."""
    a, name = s['spend_api'], s['name']
    status = a['status']
    if status == 'yes':
        lead = 'Yes.'
        body = (f'`{a["endpoint"]}` returns {lower_first(a["returns"])}' if a['endpoint'] and a['returns']
                else f'{name} returns your {noun(s)} from its API')
    elif status == 'partial':
        lead = 'Partly.'
        body = f'{name}’s API returns {lower_first(a["returns"])}' if a['returns'] else f'{name} reports some of it'
    elif status == 'no':
        lead = 'No.'
        body = a['notes'] or f'{name} doesn’t document a billing or usage API'
    else:
        lead = 'Not that we could find.'
        body = a['notes'] or f'{name}’s docs don’t describe a billing or usage API'
    return lead, sentence(body)


def plain(html_text):
    return re.sub(r'<[^>]+>', '', html_text).replace('`', '')


def facts_table(s):
    a = s['spend_api']
    rows = [('Billing', inline(sentence(s['billing_model'])))]
    if a['endpoint']:
        rows.append(('Endpoint', f'<code>{e(a["endpoint"])}</code>'))
    if a['auth']:
        rows.append(('Auth', inline(a['auth'])))
    if known(a['key_type']):
        rows.append(('Key', inline(a['key_type'])))
    if not a['endpoint']:
        return '\n'.join(f'      <div><dt>{k}</dt><dd>{v}</dd></div>' for k, v in rows)
    ro = {'yes': 'Yes', 'no': 'No', 'partial': 'Partly', 'unknown': 'Not documented'}[a['read_only']]
    if a['read_only_note']:
        ro += f'. {inline(a["read_only_note"])}'
    rows.append(('Read-only key', sentence(ro) if ro != 'Not documented' else ro))
    rows.append(('Rate limit', inline(sentence(a['rate_limit'])) if known(a['rate_limit']) else 'Not documented'))
    rows.append(('Freshness', inline(sentence(a['lag'])) if known(a['lag']) else 'Not documented'))
    cost = a['cost_to_call']
    rows.append(('Cost to check', 'Free' if cost == 'free' else inline(cap_first(sentence(cost))) if known(cost) else 'Not documented'))
    return '\n'.join(f'      <div><dt>{k}</dt><dd>{v}</dd></div>' for k, v in rows)


def steps(s):
    a, name = s['spend_api'], s['name']
    if not a['endpoint'] or a['status'] not in ('yes', 'partial'):
        return ''
    key = a['key_type'] if known(a['key_type']) else 'API key'
    where = (f'<a href="{e(a["key_url"])}">{e(name)}’s key settings</a>' if a['key_url']
             else f'your <a href="{e(s["website"])}">{e(name)}</a> dashboard')
    if s.get('setup_steps'):
        items = [f'<li><b>{inline(step["title"].rstrip(".") + ".")}</b> {inline(sentence(step["detail"]))} '
                 f'<a href="{e(step["url"])}">Open {e(step["link"])}</a>.</li>' for step in s['setup_steps']]
    else:
        items = [f'<li><b>Get the key.</b> {inline(cap_first(key.rstrip('.')))}, from {where}.</li>']
    if a['auth']:
        header_style = re.match(r'^[\w-]+:', a['auth'])
        auth = sentence(a['auth']) if header_style else cap_first(sentence(a['auth']))
        items.append(f'<li><b>Send it the way {e(name)} expects.</b> {inline(auth)}</li>')
    items.append(f'<li><b>Call the endpoint.</b> <code>{e(a["endpoint"])}</code></li>')
    if a['returns']:
        items.append(f'<li><b>Read the numbers.</b> It returns {inline(sentence(lower_first(a["returns"])))}</li>')
    warn = ''
    if a['read_only'] in ('no', 'partial'):
        warn = ('\n    <p class="callout"><b>About key power.</b> '
                + (inline(sentence(a['read_only_note'])) if a['read_only_note'] else f'{e(name)} doesn’t offer a key that can only read billing.')
                + ' Keep it out of code and chats, and revoke it if it leaks.</p>')
    return f'''  <section aria-labelledby="how-title">
    <h2 id="how-title">How to read it from the API</h2>
    <ol class="steps">
      {"".join(items)}
    </ol>{warn}
  </section>
'''


def caps_section(s):
    name, caps = s['name'], s['native_caps']
    if caps:
        items = []
        for c in caps:
            cls, label = kind_labels[c['kind']]
            where = f'<a href="{e(c["url"])}">{inline(c["where"])}</a>' if c['url'] else inline(c['where'])
            note = f' {inline(sentence(c["note"]))}' if c['note'] else ''
            items.append(f'<li><b>{inline(c["name"])}</b><span>{where}.{note}</span><i class="kind {cls}">{label}</i></li>')
        stops = [c for c in caps if c['kind'] in ('hard-stop', 'partial-stop')]
        full = any(c['kind'] == 'hard-stop' for c in stops)
        intro = (f'{e(name)} can stop {"" if full else "part of its "}spend on its own. Turn this on first: it works even when nothing is watching.'
                 if stops else f'{e(name)} can warn you, but nothing here stops spend on its own.')
        body = f'<p>{intro}</p>\n    <ul class="caps-list">{"".join(items)}</ul>'
    elif s['caps_status'] == 'none-documented':
        body = (f'<p>{e(name)} documents no spend cap or budget alert. On a prepaid balance, what you top up is your limit, so keep top-ups small and check the balance often.</p>'
                if s['billing_type'] == 'prepaid' else
                f'<p>{e(name)} documents no spend cap or budget alert. Nothing stops spend for you, so check the number often.</p>')
    else:
        body = f'<p>We couldn’t find a spend cap in {e(name)}’s docs. Check its billing settings for a limit or alert before you rely on it.</p>'
    return f'''  <section aria-labelledby="caps-title">
    <h2 id="caps-title">Spend caps {e(name)} offers</h2>
    {body}
  </section>
'''


def killcord_text(s):
    name, tier = s['name'], s['killcord']['tier']
    if s['slug'] in caps_only:
        return (f'Partly. {name} has no billing API, so Kill Cord can’t show its spend. Kill Cord’s caps audit '
                f'walks you through turning on {name}’s own cap and reminds you to re-check it.')
    if tier == 'built-in' and s['slug'] in no_caps_audit:
        return (f'Yes. Kill Cord shows {builtin_shows[s["slug"]]} in your Mac’s menu bar, for one account or several, says how fresh each number is, '
                f'and can alert you once when it runs low. A balance is what’s left, not spend, so it stays out of your spend totals.')
    if tier == 'built-in':
        return (f'Yes. Kill Cord shows {builtin_shows[s["slug"]]} in your Mac’s menu bar, for one account or several, says how fresh each number is, '
                f'and walks you through {name}’s own caps in its caps audit.')
    if s['killcord'].get('note'):
        return s['killcord']['note']
    if tier == 'planned':
        return (f'Not yet. {name}’s API makes it a candidate for a future Kill Cord adapter, but there’s no date. '
                f'Today Kill Cord tracks {builtin_names}.')
    if s['spend_api']['status'] in ('no', 'unknown'):
        return (f'No. Kill Cord reads spend from each provider’s API, and {name} doesn’t document one. '
                f'Kill Cord tracks {builtin_names}.')
    return f'No. Kill Cord doesn’t track {name} today. It tracks {builtin_names}.'


def killcord_section(s):
    tier = s['killcord']['tier']
    heading = {'built-in': f'Track {e(s["name"])} in your menu bar' if s['slug'] not in caps_only else f'Kill Cord and {e(s["name"])}', 'planned': 'Kill Cord and ' + e(s['name']),
               'manual': f'Track {e(s["name"])} by hand in Kill Cord', 'none': 'Kill Cord and ' + e(s['name'])}[tier]
    extra = ('<p>To connect it, click the plug in your menu bar, choose Connect a Provider, and paste the key. Kill Cord '
             f'checks it with {e(s["name"])} before it saves it. The key stays in your Mac’s Keychain and goes only to '
             f'{e(s["name"])}’s billing API. Kill Cord is free, with no account.</p>' if tier == 'built-in' and s['slug'] not in caps_only else
             '<p>Kill Cord is free, with no account, and it reads spend for ' + builtin_names + '.</p>' if tier == 'built-in' else
             (f'<p>To add it, open Settings › Providers in Kill Cord, choose Manual entry, and pick {e(s["name"])} from the '
              'services with no billing API. Kill Cord is free, with no account.</p>') if tier == 'manual' else
             (f'<p>Today Kill Cord tracks {builtin_names}. If you use any of those, it puts their spend in one glance and gets their caps turned on.</p>'
              if s['killcord'].get('note') else
              '<p>If you also use any of those, Kill Cord puts their spend in one glance and gets their caps turned on.</p>'))
    return f'''  <section aria-labelledby="kc-title" class="kc-box">
    <h2 id="kc-title">{heading}</h2>
    <p>{e(killcord_text(s))}</p>
    {extra}
    <div class="bx-cta"><a class="bx-btn" href="{{{{download_url}}}}">Download Kill Cord for Mac <span aria-hidden="true">↓</span></a></div>
    <p class="bx-meta">Free with no account · Keys stay in your Keychain · macOS 14 or later</p>
  </section>
'''


def faqs(s):
    a, name, n = s['spend_api'], s['name'], s['search_name']
    lead, body = answer(s)
    out = [(f'Can I check my {n} {noun(s)} with the API?', f'{lead} {plain(body)}')]
    if a['endpoint'] and known(a['key_type']):
        out.append((f'What key do I need to check my {n} {noun(s)}?', sentence(plain(a['key_type']))
                    + (f' {plain(sentence(a["read_only_note"]))}' if a['read_only_note'] else '')))
    if known(a['lag']):
        out.append((f'How current is {name}’s number?', plain(sentence(a['lag']))))
    caps = s['native_caps']
    stops = [c for c in caps if c['kind'] in ('hard-stop', 'partial-stop')]
    if stops:
        c = stops[0]
        out.append((f'Does {name} have a spending limit?', f'Yes: {plain(c["name"])}, in {plain(c["where"])}.'
                    + (f' {plain(sentence(c["note"]))}' if c['note'] else '')))
    elif caps:
        out.append((f'Does {name} have a spending limit?', f'Not one that stops spend. It offers {plain(caps[0]["name"]).lower()}, which only warns you.'))
    else:
        out.append((f'Does {name} have a spending limit?', 'Not one we could find in its docs.'))
    out += [(f['q'], f['a']) for f in s.get('extra_faq', [])]
    out.append((f'Does Kill Cord track {name}?', killcord_text(s)))
    return out


def related(s):
    same = [r for r in published if r['category'] == s['category'] and r['slug'] != s['slug']]
    others = [r for r in published if r['category'] != s['category'] and r['killcord']['tier'] == 'built-in' and r['slug'] != s['slug']]
    picks = (same + others)[:6]
    items = ''.join(f'<li><a href="{url_for(r)}">{e(r["search_name"])}</a><span>Spend API: {e(answer(r)[0].rstrip('.'))}</span></li>' for r in picks)
    key = s['category']
    return f'''  <section aria-labelledby="related-title">
    <h2 id="related-title">Related services</h2>
    <ul class="related">{items}</ul>
    <p><a href="{category_url(key)}">More {e(categories[key][1])}</a> · <a href="/track/">Every service</a></p>
  </section>
'''


def intro(s):
    a, name = s['spend_api'], s['name']
    stops = any(c['kind'] in ('hard-stop', 'partial-stop') for c in s['native_caps'])
    full = any(c['kind'] == 'hard-stop' for c in s['native_caps'])
    stop_text = f'the cap that stops {name} spend on its own' if full else f'the cap that stops some {name} spend on its own'
    caps = f'and {stop_text}' if stops else f'and whether {name} can cap spend at all'
    if a['status'] == 'yes':
        return f'{name} tells you your {noun(s)} with one API call. Here’s the call, the key it needs, {caps}.'
    if a['status'] == 'partial':
        return f'{name}’s API tells you part of it. Here’s what it returns, what it leaves out, {caps}.'
    tail = stop_text if stops else f'whether {name} can cap spend at all'
    return f'{name} has no documented usage API, so the number lives in its console. Here’s where to look, and {tail}.'


def service_page(s):
    key = s['category']
    lead, body = answer(s)
    faq = faqs(s)
    faq_html = ''.join(f'<details><summary>{e(q)}</summary><p>{e(ans)}</p></details>' for q, ans in faq)
    notes = s['spend_api']['notes'] if s['spend_api']['status'] in ('yes', 'partial') else None
    note_html = f'\n    <p class="fine">{inline(sentence(notes))}</p>' if notes else ''
    sources = ''.join(f'<li><a href="{e(u)}">{e(re.sub(r"^https?://", "", u))}</a></li>' for u in s['sources'])
    content = f'''<section class="bx-hero page-hero" aria-labelledby="page-title">
  <div class="bx-wrap page-head">
    <nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Kill Cord</a></li><li><a href="/track/">Track API spend</a></li><li><a href="{category_url(key)}">{e(categories[key][1])}</a></li><li aria-current="page">{e(s["search_name"])}</li></ol></nav>
    {tier_badge(s)}
    <h1 id="page-title">{e(h1_for(s))}</h1>
    <p class="bx-lede">{inline(s.get('page', {}).get('lede') or intro(s))}</p>
  </div>
</section>

<div class="bx-wrap prose">
  <section aria-labelledby="answer-title" class="answer">
    <h2 id="answer-title">Can you read your {e(s["name"])} {noun(s)} from the API?</h2>
    <p class="answer-lead"><b>{e(lead)}</b> {inline(body)}</p>{note_html}
    <dl class="readings api-facts">
{facts_table(s)}
    </dl>
  </section>

{steps(s)}{caps_section(s)}{killcord_section(s)}
  <section aria-labelledby="faq-title">
    <h2 id="faq-title">Questions</h2>
    <div class="bx-faq faq-list">{faq_html}</div>
  </section>

{cluster_nav(s['slug']) if s['slug'] == 'anthropic' else ''}{related(s)}
  <section aria-labelledby="sources-title">
    <h2 id="sources-title">Sources</h2>
    <p>Every fact on this page comes from {e(s["name"])}’s own docs. Anything they don’t say is marked “Not documented”. Last checked {s["last_verified"]}.</p>
    <ul class="sources">{sources}</ul>
  </section>
</div>'''
    description = meta_description(s)
    return {
        'path': path_for(s), 'title': title_for(s), 'description': description,
        'og_title': h1_for(s), 'og_description': description,
        'body_class': 'article-page track-page', 'updated': s['last_verified'], 'content': content,
        'crumbs': [('Kill Cord', site), ('Track API spend', site + 'track/'),
                   (categories[key][1], site + category_url(key)[1:]), (s['search_name'], site + url_for(s)[1:])],
        'faq': faq,
    }


def meta_description(s):
    a, name, n = s['spend_api'], s['name'], s['search_name']
    if a['status'] == 'yes' and a['endpoint']:
        call = a['endpoint'].split(' ')[0] + ' ' + re.sub(r'^https?://[^/]+', '', a['endpoint'].split(' ', 1)[-1]).split('?')[0]
        text = f'Check your {n} {noun(s)} with {call}: the key it needs and how fresh it is.'
        if len(text) > 110:
            text = f'Check your {n} {noun(s)} from the API: the endpoint and the key it needs.'
    elif a['status'] == 'partial':
        text = f'What {name}’s API can and can’t tell you about your {noun(s)}, and the key it needs.'
    else:
        text = f'{name} has no documented usage API. Here’s where to check your {n} {noun(s)} instead.'
    return pad(text, description_clauses(s))


def description_clauses(s):
    """Short true facts to bring a meta description up to 140 to 160 characters."""
    a, name, caps = s['spend_api'], s['name'], s['native_caps']
    kinds = {c['kind'] for c in caps}
    out = []
    if 'hard-stop' in kinds:
        out.append(f' {name} can hard-stop spend.')
    elif kinds & {'partial-stop', 'auto-recharge-off'}:
        out.append(' Its caps stop only some spend.')
    elif caps:
        out.append(' Its only cap is an alert.')
    elif s['caps_status'] == 'none-documented':
        out.append(' It documents no spend cap.')
    tier = s['killcord']['tier']
    out.append(' Kill Cord audits its cap.' if s['slug'] in caps_only else
               ' Kill Cord shows it in your menu bar.' if tier == 'built-in' else
               ' Not in Kill Cord yet.' if tier == 'planned' else
               ' Kill Cord tracks it as a manual entry.' if tier == 'manual' else '')
    if a['endpoint']:
        out.append({'yes': ' A read-only key works.', 'no': ' No key is read-only.'}.get(a['read_only'], ''))
    elif a['status'] == 'partial':
        out.append(' It has no usage endpoint.')
    out += [' Checked against official docs.', ' From official docs.']
    return [c for c in out if c]


def pad(text, clauses, low=140, high=160):
    if len(text) > high:
        return text[:high - 3].rsplit(' ', 1)[0] + '…'
    for clause in clauses:
        if len(text) >= low:
            break
        if 'official docs' in clause and 'official docs' in text:
            continue
        if len(text + clause) <= high:
            text += clause
    return text


def table(rows, billing=False):
    body = []
    for s in rows:
        a = s['spend_api']
        api_cell = {'yes': 'Yes', 'partial': 'Partly', 'no': 'No', 'unknown': 'Not documented'}[a['status']]
        stops = [c for c in s['native_caps'] if c['kind'] in ('hard-stop', 'partial-stop')]
        cap_cell = 'Hard stop' if any(c['kind'] == 'hard-stop' for c in stops) else 'Partial stop' if stops else \
            'Alert only' if s['native_caps'] else 'None found'
        kc = 'Caps audit' if s['slug'] in caps_only else {'built-in': 'Built in', 'manual': 'Manual entry', 'planned': 'Not yet', 'none': 'No'}[s['killcord']['tier']]
        body.append(f'<tr><th scope="row"><a href="{url_for(s)}">{e(s["search_name"])}</a></th>'
                    f'<td data-label="Spend API">{api_cell}</td><td data-label="Native cap">{cap_cell}</td>'
                    f'<td data-label="Kill Cord">{kc}</td>'
                    + (f'<td data-label="How it bills">{inline(sentence(s["billing_model"]))}</td>' if billing else '') + '</tr>')
    return (f'<div class="table-wrap"><table class="coverage{" billing" if billing else ""}"><thead><tr><th scope="col">Service</th>'
            '<th scope="col">Spend API</th><th scope="col">Native cap</th><th scope="col">Kill Cord</th>'
            + ('<th scope="col">How it bills</th>' if billing else '') + '</tr></thead>'
            f'<tbody>{"".join(body)}</tbody></table></div>')


def order(rows):
    tiers = {'built-in': 0, 'manual': 1, 'planned': 2, 'none': 3}
    return sorted(rows, key=lambda s: (tiers[s['killcord']['tier']], s['search_name'].lower()))


def names(rows, limit=5):
    items = [f'<a href="{url_for(r)}">{e(r["search_name"])}</a>' for r in rows]
    if len(items) > limit:
        return ', '.join(items[:limit]) + f' and {len(items) - limit} more'
    return items[0] if len(items) == 1 else ', '.join(items[:-1]) + ' and ' + items[-1]


def count(rows, one, many):
    return f'{len(rows)} {one if len(rows) == 1 else many}'


def clauses(parts):
    parts = [p for p in parts if p]
    if len(parts) < 3:
        return ' and '.join(parts)
    return '; '.join(parts[:-1]) + '; and ' + parts[-1]


def category_overview(label, rows):
    """A summary of how this category bills and caps, computed from the records on the page."""
    by = lambda test: [r for r in rows if test(r)]
    billing = clauses([
        (lambda g: g and f'{count(g, "runs", "run")} on a prepaid balance or credits you top up ({names(g)})')(by(lambda r: r['billing_type'] == 'prepaid')),
        (lambda g: g and f'{count(g, "bills", "bill")} for usage after the fact ({names(g)})')(by(lambda r: r['billing_type'] == 'usage')),
        (lambda g: g and f'{count(g, "sells", "sell")} a monthly allowance of credits or requests ({names(g)})')(by(lambda r: r['billing_type'] == 'quota')),
        (lambda g: g and f'{count(g, "mixes", "mix")} models, such as a plan plus usage or credits plus invoicing ({names(g)})')(by(lambda r: r['billing_type'] == 'mixed')),
    ])
    status = lambda v: by(lambda r: r['spend_api']['status'] == v)
    api = ' '.join(x for x in [
        status('yes') and f'{count(status("yes"), "returns", "return")} a balance, credits or spend from one call ({names(status("yes"))}).',
        status('partial') and f'{count(status("partial"), "gives", "give")} part of it, such as usage without dollars or spend without a balance ({names(status("partial"))}).',
        status('no') and f'{count(status("no"), "shows", "show")} it only in the console ({names(status("no"))}).',
        status('unknown') and f'{count(status("unknown"), "doesn’t", "don’t")} document it either way ({names(status("unknown"))}).',
    ] if x)
    kinds = lambda r: {c['kind'] for c in r['native_caps']}
    hard = by(lambda r: 'hard-stop' in kinds(r))
    some = by(lambda r: 'hard-stop' not in kinds(r) and kinds(r) & {'partial-stop', 'auto-recharge-off'})
    alert = by(lambda r: kinds(r) == {'alert-only'})
    none = by(lambda r: not r['native_caps'])
    caps = ' '.join(x for x in [
        hard and f'{count(hard, "can", "can")} hard-stop spend on {"its" if len(hard) == 1 else "their"} own ({names(hard)}).',
        some and f'{count(some, "stops", "stop")} only some spend or {"caps" if len(some) == 1 else "cap"} top-ups ({names(some)}).',
        alert and f'{count(alert, "only sends", "only send")} alerts ({names(alert)}).',
        none and f'{count(none, "documents", "document")} no cap at all ({names(none)}), so a small balance or a close watch is the only limit.',
    ] if x)
    power = by(lambda r: r['spend_api']['endpoint'] and r['spend_api']['read_only'] == 'no')
    readonly = by(lambda r: r['spend_api']['endpoint'] and r['spend_api']['read_only'] == 'yes')
    keys = ' '.join(x for x in [
        power and f'{count(power, "has", "have")} no read-only key, so the key that reads billing can do more than read it ({names(power)}).',
        readonly and f'{count(readonly, "offers", "offer")} a read-only key ({names(readonly)}).',
    ] if x)
    fresh = by(lambda r: known(r['spend_api']['lag']))[:4]
    freshness = ' '.join(f'<a href="{url_for(r)}">{e(r["search_name"])}</a>: {inline(sentence(lower_first(r["spend_api"]["lag"])))}'
                         for r in fresh)
    paid = by(lambda r: known(r['spend_api']['cost_to_call']) and r['spend_api']['cost_to_call'] != 'free')
    free = by(lambda r: r['spend_api']['cost_to_call'] == 'free')
    checking = ' '.join(x for x in [
        free and f'Checking is free for {len(free)} ({names(free)}).',
        ' '.join(f'<a href="{url_for(r)}">{e(r["search_name"])}</a> charges for each check: {inline(sentence(lower_first(r["spend_api"]["cost_to_call"])))}'
                 for r in paid),
    ] if x)
    built = by(lambda r: r['killcord']['tier'] == 'built-in')
    tracked = (f'Kill Cord covers {len(built)} of these today ({names(built)}).' if built else
               f'Kill Cord doesn’t track any of these yet. It tracks {builtin_names}.')
    items = [('How they bill', billing[:1].upper() + billing[1:] + '.' if billing else ''), ('Reading it from an API', api),
             ('Caps', caps), ('Key power', keys), ('How fresh the numbers are', freshness),
             ('What a check costs', checking), ('Kill Cord', tracked)]
    lis = ''.join(f'<li><b>{head}.</b> {body}</li>' for head, body in items if body)
    return f'''  <section aria-labelledby="overview-title">
    <h2 id="overview-title">How these services bill and cap spend</h2>
    <ul class="overview">{lis}</ul>
  </section>
'''


def hub_pages():
    used = [k for k in categories if any(s['category'] == k for s in published)]
    claude_line = ('\n    <p>Claude API guides: ' + ' · '.join(f'<a href="/track/{c["slug"]}/">{e(c["nav"])}</a>' for c in cluster)
                   + '.</p>')
    sections = []
    for k in used:
        slug, label, blurb = categories[k]
        rows = order([s for s in published if s['category'] == k])
        sections.append(f'''  <section aria-labelledby="{slug}-title">
    <h2 id="{slug}-title"><a href="{category_url(k)}">{e(label)}</a></h2>
    <p>{e(blurb)}</p>
    {table(rows)}{claude_line if k == 'llm' else ''}
  </section>
''')
    nav = ''.join(f'<li><a href="{category_url(k)}">{e(categories[k][1])}</a></li>' for k in used)
    with_api = sum(s['spend_api']['status'] == 'yes' for s in published)
    hub = {
        'path': 'track/index.html', 'title': 'Check API Usage, Credits and Spend | Kill Cord',
        'description': f'How to read your balance, credits or spend from {len(published)} API services: the endpoint, the key each needs, and the spend caps that stop a runaway bill.',
        'og_title': 'How to check API usage, credits and spend',
        'og_description': 'The endpoint, the key, and the native spend caps for each API service, from official docs.',
        'body_class': 'article-page track-page', 'updated': max(s['last_verified'] for s in published),
        'crumbs': [('Kill Cord', site), ('Track API spend', site + 'track/')],
        'content': f'''<section class="bx-hero page-hero" aria-labelledby="page-title">
  <div class="bx-wrap page-head">
    <nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Kill Cord</a></li><li aria-current="page">Track API spend</li></ol></nav>
    <p class="bx-badge"><i aria-hidden="true"></i>{len(published)} services · From official docs</p>
    <h1 id="page-title">Check your API usage, credits and spend</h1>
    <p class="bx-lede">Every usage-billed API hides its balance somewhere different. Here’s where each one keeps it, whether you can read it with a key, and which caps stop spend before the bill does. {with_api} of these {len(published)} answer with one API call.</p>
    <nav aria-label="Categories"><ul class="cat-nav">{nav}</ul></nav>
  </div>
</section>

<div class="bx-wrap prose wide">
{"".join(sections)}  <section aria-labelledby="how-read-title">
    <h2 id="how-read-title">How to read these pages</h2>
    <ul>
      <li><b>Spend API</b> is Yes when an endpoint returns your balance, credits left, or spend in money. Partly means it returns usage counts or spend without a balance.</li>
      <li><b>Native cap</b> is the service’s own control. A hard stop refuses requests past the limit. An alert only tells you.</li>
      <li><b>Kill Cord</b> is Built in for the eight providers the app reads today. Not yet means the API is suitable, but no adapter exists.</li>
    </ul>
    <p>Facts come from each service’s official docs, checked {max(s['last_verified'] for s in published)}. Anything the docs don’t say is marked “Not documented”.</p>
  </section>
</div>''',
    }
    pages = [hub]
    for k in used:
        slug, label, blurb = categories[k]
        rows = order([s for s in published if s['category'] == k])
        names = [s['search_name'] for s in rows]
        listing = ', '.join(names[:3]) + (', and more' if len(names) > 3 else '')
        title = f'{label}: Check Usage and Spend | Kill Cord'
        if len(title) > 60:
            title = f'{label}: Usage and Spend'
        desc = f'How to check usage, credits and spend for {listing}: the endpoint, the key, and the spend caps each offers.'
        if len(desc) > 160:
            desc = f'How to check usage, credits and spend for {len(rows)} {label.lower()}: the endpoint, the key, and the caps each offers.'
        with_api = sum(r['spend_api']['status'] == 'yes' for r in rows)
        desc = pad(desc, [f' {with_api} of {len(rows)} answer with one API call.', ' Checked against official docs.', ' From official docs.'])
        pages.append({
            'path': f'track/{slug}/index.html', 'title': title, 'description': desc,
            'og_title': f'{label}: how to check usage and spend', 'og_description': desc,
            'body_class': 'article-page track-page', 'updated': max(s['last_verified'] for s in rows),
            'crumbs': [('Kill Cord', site), ('Track API spend', site + 'track/'), (label, site + f'track/{slug}/')],
            'content': f'''<section class="bx-hero page-hero" aria-labelledby="page-title">
  <div class="bx-wrap page-head">
    <nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Kill Cord</a></li><li><a href="/track/">Track API spend</a></li><li aria-current="page">{e(label)}</li></ol></nav>
    <p class="bx-badge"><i aria-hidden="true"></i>{len(rows)} services</p>
    <h1 id="page-title">{e(label)}: check usage and spend</h1>
    <p class="bx-lede">{e(blurb)} Here’s whether each one tells you its number over the API, and which caps stop spend on their own.</p>
  </div>
</section>

<div class="bx-wrap prose wide">
{category_overview(label, rows)}  <section aria-labelledby="list-title">
    <h2 id="list-title">Services</h2>
    {table(rows, billing=True)}
  </section>
  <section aria-labelledby="more-title">
    <h2 id="more-title">More categories</h2>
    <ul class="cat-nav">{"".join(f'<li><a href="{category_url(o)}">{e(categories[o][1])}</a></li>' for o in used if o != k)}</ul>
  </section>
</div>''',
        })
    return pages


def validate():
    allowed = {'billing_type': {'prepaid', 'usage', 'quota', 'mixed'}, 'caps_status': {'found', 'none-documented', 'unknown'}}
    for s in services:
        assert s['category'] in categories, f'{s["slug"]}: unknown category {s["category"]}'
        assert s['killcord']['tier'] in ('built-in', 'manual', 'planned', 'none'), f'{s["slug"]}: unknown tier'
        assert set(s['killcord']) <= {'tier', 'note'}, f'{s["slug"]}: unknown killcord field'
        # A manual preset says what Kill Cord does for it, since there's no API to read.
        assert s['killcord']['tier'] != 'manual' or s['killcord'].get('note'), f'{s["slug"]}: manual without a note'
        assert s.get('noun', 'spend') in ('balance', 'credits', 'usage', 'spend'), f'{s["slug"]}: unknown noun'
        assert s['spend_api']['status'] in ('yes', 'partial', 'no', 'unknown'), f'{s["slug"]}: unknown API status'
        assert s['spend_api']['read_only'] in ('yes', 'no', 'partial', 'unknown'), f'{s["slug"]}: unknown read_only'
        for field, values in allowed.items():
            assert s[field] in values, f'{s["slug"]}: unknown {field}'
        for c in s['native_caps']:
            assert c['kind'] in kind_labels, f'{s["slug"]}: unknown cap kind {c["kind"]}'
        assert s['sources'], f'{s["slug"]}: no sources'
        for f in s.get('extra_faq', []):
            assert set(f) == {'q', 'a'}, f'{s["slug"]}: extra_faq fields'
        for step in s.get('setup_steps', []):
            assert set(step) == {'title', 'detail', 'url', 'link'}, f'{s["slug"]}: setup step fields'
        if s['publish'] and s['killcord']['tier'] == 'built-in':
            assert s['slug'] in builtin_shows or s['slug'] in caps_only, f'{s["slug"]}: built-in without app copy'


cluster = json.loads((root / 'data/claude-cluster.json').read_text())


def cluster_nav(current):
    links = [('anthropic', 'Billing API', '/track/anthropic/')] + [(c['slug'], c['nav'], f'/track/{c["slug"]}/') for c in cluster]
    current_attr = ' aria-current="page"'
    items = ''.join(f'<li><a href="{url}"{current_attr if slug == current else ""}>{e(label)}</a></li>'
                    for slug, label, url in links)
    return f'''  <section aria-labelledby="cluster-title">
    <h2 id="cluster-title">More on Claude API spend</h2>
    <ul class="cat-nav">{items}</ul>
  </section>

'''


def cluster_page(c):
    sections = []
    for sec in c['sections']:
        body = ''.join(f'\n    <p>{inline(x)}</p>' for x in sec.get('paras', []))
        if sec.get('list'):
            body += '\n    <ul>' + ''.join(f'<li>{inline(x)}</li>' for x in sec['list']) + '</ul>'
        if sec.get('after'):
            body += f'\n    <p>{inline(sec["after"])}</p>'
        sections.append(f'''  <section aria-labelledby="{sec["id"]}-title">
    <h2 id="{sec["id"]}-title">{inline(sec["h2"])}</h2>{body}
  </section>
''')
    faq = [(f['q'], f['a']) for f in c['faq']]
    faq_html = ''.join(f'<details><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in faq)
    sources = ''.join(f'<li><a href="{e(u)}">{e(re.sub(r"^https?://", "", u))}</a></li>' for u in c['sources'])
    anthropic = by_slug['anthropic']
    content = f'''<section class="bx-hero page-hero" aria-labelledby="page-title">
  <div class="bx-wrap page-head">
    <nav class="crumbs" aria-label="Breadcrumb"><ol><li><a href="/">Kill Cord</a></li><li><a href="/track/">Track API spend</a></li><li><a href="/track/anthropic/">Claude API</a></li><li aria-current="page">{e(c["nav"])}</li></ol></nav>
    <p class="bx-badge tier-on"><i aria-hidden="true"></i>Claude API · Built into Kill Cord</p>
    <h1 id="page-title">{e(c["h1"])}</h1>
    <p class="bx-lede">{inline(c["lede"])}</p>
  </div>
</section>

<div class="bx-wrap prose">
{"".join(sections)}{killcord_section(anthropic)}
  <section aria-labelledby="faq-title">
    <h2 id="faq-title">Questions</h2>
    <div class="bx-faq faq-list">{faq_html}</div>
  </section>

{cluster_nav(c["slug"])}  <section aria-labelledby="sources-title">
    <h2 id="sources-title">Sources</h2>
    <p>Every fact on this page comes from Anthropic’s own docs and help center. Last checked {anthropic["last_verified"]}.</p>
    <ul class="sources">{sources}</ul>
  </section>
</div>'''
    return {
        'path': f'track/{c["slug"]}/index.html', 'title': c['title'], 'description': c['description'],
        'og_title': c['h1'], 'og_description': c['description'], 'body_class': 'article-page track-page',
        'updated': anthropic['last_verified'], 'content': content, 'faq': faq,
        'crumbs': [('Kill Cord', site), ('Track API spend', site + 'track/'), ('Claude API', site + 'track/anthropic/'),
                   (c['nav'], site + f'track/{c["slug"]}/')],
    }


def pages():
    validate()
    slugs = {categories[k][0] for k in categories}
    clash = slugs & {s['slug'] for s in services}
    assert not clash, f'Service slug clashes with a category: {clash}'
    taken = {s['slug'] for s in services} | slugs
    assert not taken & {c['slug'] for c in cluster}, 'Cluster slug clashes with a service or category'
    return hub_pages() + [service_page(s) for s in published] + [cluster_page(c) for c in cluster]
