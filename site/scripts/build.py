from html import escape
from pathlib import Path
from string import Template
import json
import shutil

import directory

root = Path(__file__).resolve().parent.parent
source = root / 'src'
output = root / 'dist'
layout = Template((source / 'layouts/base.html').read_text())
download_url = 'https://github.com/coreyhaines31/killcord/releases/latest/download/KillCord.dmg'
partials = {name: (source / f'layouts/{name}.html').read_text().strip() for name in ('header', 'footer', 'popover')}


def fill(text):
    text = text.replace('{{popover}}', partials['popover'])
    return text.replace('{{download_url}}', download_url)


shared = {name: fill(partials[name]) for name in ('header', 'footer')}
pages = json.loads((source / 'pages.json').read_text()) + directory.pages()
site = 'https://killcord.app/'
app = {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    'name': 'Kill Cord',
    'description': "A free macOS menu bar app that shows today's and this month's API spend across providers, and walks you through turning on each provider's own spend caps.",
    'url': site,
    'applicationCategory': 'DeveloperApplication',
    'operatingSystem': 'macOS 14 or later',
    'license': 'https://fsl.software/FSL-1.1-MIT.template.md',
    'downloadUrl': 'https://github.com/coreyhaines31/killcord/releases/latest',
    'image': site + 'og.png',
    'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
}


def structured_data(page, url):
    if page['path'] == 'index.html':
        return json.dumps(app, ensure_ascii=False).replace('</', '<\\/')
    crumbs = page.get('crumbs') or [('Kill Cord', site), (page['crumb'], url)]
    graph = [app, {'@type': 'BreadcrumbList', 'itemListElement': [
        {'@type': 'ListItem', 'position': i, 'name': name, 'item': item} for i, (name, item) in enumerate(crumbs, 1)]}]
    if page.get('faq'):
        graph.append({'@type': 'FAQPage', 'mainEntity': [
            {'@type': 'Question', 'name': q, 'acceptedAnswer': {'@type': 'Answer', 'text': a}} for q, a in page['faq']]})
    return json.dumps({'@context': 'https://schema.org', '@graph': graph}, ensure_ascii=False).replace('</', '<\\/')


expected = {Path(page['path']) for page in pages} | {Path('sitemap.xml')}
assets = {path.relative_to(source / 'assets') for path in (source / 'assets').rglob('*') if path.is_file() and path.name != '.DS_Store'}
if output.exists():
    for file in output.rglob('*'):
        if file.is_file() and file.relative_to(output) not in expected | assets:
            file.unlink()
for asset in assets:
    target = output / asset
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'assets' / asset, target)
for page in pages:
    path = page['path']
    values = {key: escape(page[key], quote=True) for key in ('title', 'description', 'og_title', 'og_description', 'body_class')}
    values.update(shared)
    values['url'] = site + path.removesuffix('index.html')
    values['structured_data'] = structured_data(page, values['url'])
    values['og_image'] = site + 'og.png'
    # Only the homepage mounts the app's popover.
    values['page_css'] = '  <link rel="stylesheet" href="/popover.css">\n' if path == 'index.html' else ''
    values['content'] = fill(page['content'] if 'content' in page else (source / 'pages' / path).read_text().strip())
    target = output / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(layout.substitute(values))
entries = sorted((site + page['path'].removesuffix('index.html'), page['updated']) for page in pages)
(output / 'sitemap.xml').write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + ''.join(f'  <url><loc>{escape(url)}</loc><lastmod>{updated}</lastmod></url>\n' for url, updated in entries)
    + '</urlset>\n')
print(f'Built {len(pages)} page(s) and the sitemap.')
