from html import unescape
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import urlsplit, unquote


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.links = []
        self.headings = []
        self.refs = []
        self.images = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
        if tag in ('a', 'use'):
            self.links.append(attrs.get('href', ''))
        if tag == 'img':
            self.images.append(attrs)
            self.refs.append(attrs.get('src', ''))
        if tag in ('h1', 'h2'):
            self.headings.append(tag)
        if tag == 'link' and attrs.get('href', '').endswith(('.css', '.svg', '.png', '.ico')):
            self.refs.append(attrs['href'])


root = Path(__file__).resolve().parent.parent / 'dist'
pages = {}
for file in root.rglob('*.html'):
    page = Page()
    text = file.read_text()
    page.feed(text)
    pages[file] = page
    assert len(page.ids) == len(set(page.ids)), f'Duplicate IDs: {file}'
    assert page.headings.count('h1') == 1, f'Exactly one main heading required: {file}'
    assert page.headings.count('h2') >= (6 if file == root / 'index.html' else 2), f'Missing sections: {file}'
    assert all('alt' in image for image in page.images), f'Image without alt: {file}'
    title = unescape(re.search(r'<title>(.*?)</title>', text, re.S).group(1))
    description = unescape(re.search(r'<meta name="description" content="(.*?)"', text).group(1))
    # Longer titles and descriptions get cut off in search results.
    assert len(title) <= 60, f'Title over 60 characters ({len(title)}): {file}'
    # Search engines show about 155 characters; much shorter wastes the snippet.
    assert 120 <= len(description) <= 160, f'Description should be 120 to 160 characters ({len(description)}): {file}'
    # Kill Cord's copy rule: no em dashes anywhere user-facing.
    assert '—' not in text and '&mdash;' not in text, f'Em dash in copy: {file}'

for file, page in pages.items():
    for ref in page.links + page.refs:
        assert ref, f'Empty reference: {file}'
        url = urlsplit(ref)
        if url.scheme or url.netloc:
            continue
        path = unquote(url.path)
        target = (root / path.lstrip('/')) if path.startswith('/') else (file.parent / path)
        if not path:
            target = file
        if target.is_dir():
            target = target / 'index.html'
        assert target.is_file(), f'Missing target: {ref} in {file}'
        if url.fragment:
            assert target in pages and unquote(url.fragment) in pages[target].ids, f'Missing anchor: {ref} in {file}'
for file in root.rglob('*'):
    if file.suffix in ('.html', '.css', '.svg', '.xml', '.txt'):
        text = file.read_text()
        assert not re.search(r'[ \t]+$', text, re.M), f'Trailing whitespace: {file}'
        # The IndexNow key file must hold exactly the key.
        assert text.endswith('\n') or re.fullmatch(r'[0-9a-f]{32}', text), f'Missing final newline: {file}'
        assert '&amp;amp;' not in text, f'Double-escaped ampersand: {file}'
print(f'Passed: {len(pages)} pages; structure, alt text, title and description lengths, no em dashes, unique IDs, internal links, local assets, and whitespace.')
