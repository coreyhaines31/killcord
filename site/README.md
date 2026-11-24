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

`/teams/` collects the Kill Cord Teams waitlist. Its form posts to `/api/teams-waitlist/` (with the trailing slash: `trailingSlash: true` 308-redirects the bare path, and a redirected POST loses its body in some clients). `api/teams-waitlist.js`:

- validates the email, company size and providers, and drops bots that fill the hidden `website` field;
- upserts the row into `site.teams_waitlist`: a repeat signup with the same email updates the answers and keeps the first `ref`;
- rate-limits: 5 signups an hour per IP (stored only as an HMAC), and one change a minute per email (429);
- sends one welcome email, once per address, through PostShiba HTTP inject from `corey@mail.killcord.app` (a PostShiba inbox, 7-day retention, so replies land there), with a signed `/api/teams-waitlist-unsubscribe/?token=` link and `List-Unsubscribe` headers. A failed send is logged and retried on the next signup with that email.

`api/teams-waitlist-unsubscribe.js` shows a confirm button on GET (so link scanners can't unsubscribe anyone) and sets `unsubscribed_at` on POST. `api/_waitlist.js` holds the shared code; files starting with `_` aren't routes. No npm dependencies: Postgres goes over Neon's HTTP SQL endpoint.

Vercel env (Production and Preview, all sensitive):

| Name | What |
|---|---|
| `WAITLIST_DATABASE_URL` | Neon `killcord-cloud` (`royal-cell-20606862`), branch `main`, database `killcord`, as role `kc_waitlist`. Read at build time to open the form, and by the functions. |
| `WAITLIST_HMAC_KEY` | Signs unsubscribe tokens and hashes IPs. Rotating it breaks links in emails already sent. |
| `WAITLIST_REPLY_TO` | Optional. Where replies to the welcome email go; set in Vercel so the inbox stays out of the repo. Without it, replies go to the sending address. |
| `POSTSHIBA_INJECT_AUTH` | `username:password` of a PostShiba SMTP credential on the `coreys-apps` cluster. |

Without the first two the page says signups open soon and the functions answer 503.

### Database

The table lives in its own `site` schema so the cloud app's Prisma-managed `public` schema never sees it. `kc_waitlist` can only `SELECT`, `INSERT` and `UPDATE` that table. Apply a migration as `kc_owner`, and set the role's password out of band:

```sh
psql "$(neonctl connection-string main --project-id royal-cell-20606862 --role-name kc_owner --database-name killcord)" \
  -v ON_ERROR_STOP=1 -f db/migrations/001_teams_waitlist.up.sql   # .down.sql reverts it, dropping every signup
```

Read the list with `psql ... -c "SELECT email, company_size, providers, ref, must_have, created_at FROM site.teams_waitlist WHERE unsubscribed_at IS NULL ORDER BY created_at"`.

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
