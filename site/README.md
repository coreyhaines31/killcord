# killcord.app

The static site for https://killcord.app, generated from shared layouts. The app lives one folder up.

## Editing

- `src/layouts/base.html`: document head and metadata. `header.html` and `footer.html` are the shared header and footer (with the family panel). `popover.html` is the hero's static Kill Cord panel, with sample data.
- `src/pages/`: page content inside the main element. `src/pages.json`: titles, descriptions, and `updated` dates for the sitemap.
- `src/assets/`: styles, icons, the social card, and robots.txt.

## API spend directory (`/track/`)

`data/services.json` holds one record per API service: its billing model, the balance or usage endpoint (auth, key type, read-only key, rate limit, freshness), its native spend caps, and Kill Cord's support tier. Facts come only from each vendor's official docs or SDK source; anything they don't say stays `"unknown"` and shows as "Not documented". `scripts/directory.py` turns every record with `"publish": true` into `/track/<slug>/`, plus the `/track/` hub and one hub per category, all in the sitemap.

Kill Cord's tier must match the app: `built-in` only for providers in `KillCordCore/Provider.swift`, `planned` only for adapters the balance-API research recommends (no dates promised), `none` otherwise. `data/claude-cluster.json` holds the Claude API guides (usage, credits, cost, organization usage). Each targets one query; `/track/anthropic/` targets the Claude billing API. A record can override its page title, H1 and lede with `page`, its wording with `noun`, its setup with `setup_steps`, its FAQ with `extra_faq`, and its Kill Cord line with `killcord.note`. Publish only records whose spend API status and caps status are known.

To add a page, add or fix the record, set `publish`, update `last_verified`, and run `make lint`.

Run `make build` to generate `dist/`, or `make lint` to build and check structure, alt text, title and description lengths, em dashes, internal links, and assets. `make images` re-renders the social card from `scripts/og.html` and the touch icon from the mac-app-kit icon. The build uses Python's standard library only.

The look is the Mac app family's Brushed design: `src/assets/brushed.css`, `popover.css`, and `family/` are copied from `mac-app-kit/site-kit` (edit them there, then copy them in), and `styles.css` maps this site's sections onto them. Kill Cord's lime `#7ea81f` appears only as pilot lights; the hero panel's nameplate light uses the app's own red stop colour, like the real panel.

Copy follows the repo rule: no em dashes anywhere user-facing (`make lint` checks).

## Teams waitlist

`/teams/` collects the Kill Cord Teams waitlist. Its form posts to `api/teams-waitlist.js`, a Vercel function that creates the subscriber in Kit with the custom fields `kc_company_size`, `kc_providers`, `kc_ref` and `kc_must_have`, adds them to the Teams form, and tags them `killcord-teams-waitlist` (tag id 26383705, or `KIT_TEAMS_TAG_ID`).

The form stays disabled until Vercel has `KIT_TEAMS_FORM_ID` (read at build time to open the form, and by the function) and `KIT_API_KEY` (a Kit v4 API key, function only). Without them the page says signups open soon and the function answers 503.

`ref` comes from `?ref=` on the page: `header`, `home`, `footer`, `track-<slug>` from the footer of each `/track/` page, and `app`, `ph`, `hn`, `x`, `li`, `newsletter` or `reddit` from launch links. The page sends `teams_waitlist_view` and `teams_waitlist_submit` to Headstream with `ref`, and pushes the same event names to `tracerkitLayer`.

## Caching

The build writes a fingerprinted copy of each stylesheet, image and font to `/_a/` (`styles.<hash>.css`) and points every page at it. `vercel.json` serves `/_a/` with `max-age=31536000, immutable`; everything else, HTML included, keeps Vercel's revalidating default. `og.png` and `favicon.ico` keep fixed URLs because other sites and browsers fetch them by name.

## Preview

```sh
make build && python3 -m http.server 4719 -d dist
```

## IndexNow

`src/assets/<key>.txt` is the IndexNow key file. After a production deploy from `main` (never a preview), run `make indexnow` from the deployed commit to tell Bing and other IndexNow engines which URLs are new or have a newer `lastmod`; `make indexnow ALL=1` sends every URL. The script refuses to run until production serves the key file and the same sitemap as `dist/`.

## Hosting

Vercel (team `coreys-apps`, project `killcord`, root directory `site`) runs `make lint` and serves `dist/`. Deploy production from `main` only, once v1 ships.
