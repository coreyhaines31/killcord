# Third-party marks

Logos are trademarks of their owners and are used only to identify the services Kill Cord reads. Kill Cord is not affiliated with, sponsored by, or endorsed by any of them.

Corey decided on 2026-11-17 to show every provider's official mark next to its name, as identification (nominative use), and to accept the risk where a vendor's guidelines ask for permission first. Those vendors are flagged below so the decision can be revisited.

Rules for a mark:

- Take the geometry from the vendor's own brand page, press kit, or site assets. Never redraw, distort, or add effects.
- Commit the vendor's file byte for byte where it is just the mark. Where the official file is a lockup (mark plus wordmark), the mark's paths are copied unchanged into a file of their own and the canvas is cropped to them. Both cases are noted below.
- Every file lives in `KillCord/Assets.xcassets/ProviderMarks/mark-<provider>.imageset` as a template image, so it draws in one colour, the panel's label ink (#161616 light, #E6E7E8 dark). A colour mark becomes the same shape in one colour.
- The provider's name always sits next to the mark, and the mark never suggests a partnership.
- The mark fills about half of its key, which leaves clear space. OpenAI's file includes its own clear space, so it draws 1.45 times larger, the same as in Fuel Gauge. Cloudflare's cloud is very wide, so it draws 1.3 times larger to stay legible.

Checked 2026-11-17.

| Provider | File | Source | Terms | Asks for permission? |
|---|---|---|---|---|
| Anthropic | `Anthropic symbol - Slate.svg`, unmodified | Press kit at https://www.anthropic.com/press-kit (zip at assets.claude.com) | https://www.anthropic.com/legal/trademark-guidelines: use only "as specifically permitted by us and only in materials we approve beforehand"; no colour or proportion changes; no implied endorsement. | Yes |
| Google Cloud and Gemini | `supercloud.svg`, unmodified (the Google Cloud cloud mark, colour) | Google's own asset: https://www.gstatic.com/pantheon/images/welcome/supercloud.svg | https://partnermarketinghub.withgoogle.com/brands/google/trademarks-and-terms/terms-and-conditions/: brand features are licensed only "provided that Google expressly approves your permission request". | Yes |
| OpenAI | `OpenAI-black-monoblossom.svg`, unmodified | https://cdn.openai.com/brand/OpenAI-Logos-2025.zip, linked from https://openai.com/brand/ | Use the logo only when it relates to OpenAI services, exactly as provided, with no added colour, never more prominent than your own brand. Permission requests go to OpenAI partner communications. | Yes |
| Vercel | `vercel-symbol-black.svg`, unmodified | https://vercel.com/geist/brands | You may use the marks to describe Vercel's products. Don't modify them, and include a visible trademark attribution (README and Settings, General). | No, for describing its products |
| Cloudflare | `cloudflare-logomark-singlecolor.svg`: the two cloud paths from `CF_logo_horizontal_singlecolor_wht.svg`, unchanged, with the canvas cropped to them | https://www.cloudflare.com/brand/logo/ | https://www.cloudflare.com/trademark/: third parties may use the marks "in word form only (word marks, not logos)"; logos need written permission. | Yes |
| Twilio | `twilio-bug.svg`: the six subpaths of the circular "bug" from the official Twilio logo on twilio.com, unchanged, with the canvas cropped to them | https://www.twilio.com/en-us (the site's own "Twilio logo" SVG) | https://www.twilio.com/en-us/legal/logo-use: the corporate logo may not be used "without our express written permission"; only the "Powered by Twilio" badge is open. | Yes |
| Neon | `neon-logomark-light-mono.svg`, unmodified | https://neon.com/brand | Use mono only when context needs it, and the logomark only where the full logo doesn't fit. Don't edit, distort, recolour, or reconfigure. | No |
| Supabase | `supabase-icon-green-transparent.svg`, unmodified (colour icon, drawn in one colour) | https://supabase.com/brand-assets | Use the logos only to refer to Supabase, and don't change the files or the logo colours. Supabase publishes no one-colour icon. | No, but one-colour rendering differs from its colours |

OpenRouter, DataForSEO, Ahrefs, Firecrawl, treg and Monid have no mark in the app yet. Until each is sourced under the rules above, Kill Cord shows the first letter of the name on the key instead, never a redrawn logo.
