# killcord.app

The static site for https://killcord.app, generated from shared layouts. The app lives one folder up.

## Editing

- `src/layouts/base.html`: document head and metadata. `header.html` and `footer.html` are the shared header and footer (with the family panel). `popover.html` is the hero's static Kill Cord panel, with sample data.
- `src/pages/`: page content inside the main element. `src/pages.json`: titles, descriptions, and `updated` dates for the sitemap.
- `src/assets/`: styles, icons, the social card, and robots.txt.

Run `make build` to generate `dist/`, or `make lint` to build and check structure, alt text, title and description lengths, em dashes, internal links, and assets. `make images` re-renders the social card from `scripts/og.html` and the touch icon from the mac-app-kit icon. The build uses Python's standard library only.

The look is the Mac app family's Brushed design: `src/assets/brushed.css`, `popover.css`, and `family/` are copied from `mac-app-kit/site-kit` (edit them there, then copy them in), and `styles.css` maps this site's sections onto them. Kill Cord's lime `#7ea81f` appears only as pilot lights.

Copy follows the repo rule: no em dashes anywhere user-facing (`make lint` checks).

## Preview

```sh
make build && python3 -m http.server 4719 -d dist
```

## Hosting

Vercel (team `coreys-apps`, project `killcord`, root directory `site`) runs `make lint` and serves `dist/`. Deploy production from `main` only, once v1 ships.
