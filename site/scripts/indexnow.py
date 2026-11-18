"""Tells IndexNow search engines (Bing, Yandex and others) which killcord.app URLs changed.

Run it after a production deploy from main, never from a preview:

    make indexnow          # URLs that are new or have a newer lastmod than before the deploy
    make indexnow ALL=1    # every URL in the sitemap

"Changed" compares the built sitemap in dist/ with the copy saved by the previous run in
.indexnow-sitemap.xml (gitignored). The script checks that production serves the key file and the
same sitemap as dist/ first, so it refuses to run before the deploy is live or against a preview.
"""
from pathlib import Path
import json
import os
import re
import sys
import urllib.error
import urllib.request

KEY = '3b42864ffaa1e2303e073bd5f31dc778'
HOST = 'killcord.app'
root = Path(__file__).resolve().parent.parent
built = (root / 'dist/sitemap.xml').read_text()
state = root / '.indexnow-sitemap.xml'


def entries(xml):
    return dict(re.findall(r'<loc>(.*?)</loc><lastmod>(.*?)</lastmod>', xml))


def fetch(path):
    try:
        with urllib.request.urlopen(f'https://{HOST}/{path}') as response:
            return response.read().decode()
    except urllib.error.HTTPError:
        return ''


if os.environ.get('VERCEL_ENV', 'production') != 'production':
    sys.exit('Not a production environment: not pinging IndexNow.')
if fetch(f'{KEY}.txt').strip() != KEY:
    sys.exit(f'https://{HOST}/{KEY}.txt does not serve the key yet: deploy to production first.')
if entries(fetch('sitemap.xml')) != entries(built):
    sys.exit('Production sitemap differs from dist/: build from the deployed commit, or wait for the deploy.')

now = entries(built)
before = {} if os.environ.get('ALL') or not state.exists() else entries(state.read_text())
urls = sorted(url for url, lastmod in now.items() if before.get(url) != lastmod)
if not urls:
    sys.exit('No changed URLs since the last ping.')
body = json.dumps({'host': HOST, 'key': KEY, 'keyLocation': f'https://{HOST}/{KEY}.txt', 'urlList': urls}).encode()
request = urllib.request.Request('https://api.indexnow.org/indexnow', data=body,
                                 headers={'Content-Type': 'application/json; charset=utf-8'})
with urllib.request.urlopen(request) as response:
    print(f'IndexNow: HTTP {response.status} for {len(urls)} URL(s)')
state.write_text(built)
