import Foundation

/// Batch 4's presets: services with no usable billing API, or one Kill Cord won't ask for because its only key can
/// do far more than read, or one whose fields couldn't be confirmed from the provider's own docs. Kept apart from
/// `corePresets` so the two lists grow without colliding. Links checked 2026-11-24.
extension ManualPreset {
    static let morePresets: [ManualPreset] = [
        ManualPreset(
            id: "apollo", name: "Apollo", billingURL: url("https://app.apollo.io/"),
            docURL: url("https://docs.apollo.io/reference/view-credit-usage-stats"),
            note: "Apollo's credit usage API needs a master API key, which can call every endpoint, so Kill Cord "
                + "doesn't ask for it.", caps: []),
        ManualPreset(
            id: "brave", name: "Brave Search API", billingURL: url("https://api-dashboard.search.brave.com/"),
            docURL: url("https://api-dashboard.search.brave.com/documentation/guides/rate-limiting"),
            note: "Brave reports the quota left only in headers on billed search calls, so reading it would cost "
                + "searches.", caps: []),
        ManualPreset(
            id: "clay", name: "Clay", billingURL: url("https://app.clay.com/"),
            docURL: url("https://www.clay.com/pricing"),
            note: "Clay shows credits in its app only. No billing API was found.", caps: []),
        ManualPreset(
            id: "cloudinary", name: "Cloudinary", billingURL: url("https://console.cloudinary.com/"),
            docURL: url("https://cloudinary.com/documentation/developer_onboarding_faq_usage_limits"),
            note: "Cloudinary's usage API needs the Admin API key and secret, which can change and delete media, so "
                + "Kill Cord doesn't ask for them.", caps: []),
        ManualPreset(
            id: "composio", name: "Composio", billingURL: url("https://platform.composio.dev/"),
            docURL: url("https://composio.dev/pricing"),
            note: "Composio shows usage in its dashboard only. No billing API was found.", caps: []),
        ManualPreset(
            id: "enrichlayer", name: "Enrich Layer", billingURL: url("https://enrichlayer.com/dashboard"),
            docURL: url("https://enrichlayer.com/docs/knowledge-base/getting-started/former-proxycurl-user"),
            note: "Enrich Layer, Proxycurl's successor, documents no credit balance endpoint.", caps: []),
        ManualPreset(
            id: "flyio", name: "Fly.io", billingURL: url("https://fly.io/dashboard"),
            docURL: url("https://fly.io/docs/about/billing/"),
            note: "Fly.io removed its billing API; usage and invoices are in the dashboard only.", caps: []),
        ManualPreset(
            id: "gladia", name: "Gladia", billingURL: url("https://app.gladia.io/"),
            docURL: url("https://www.gladia.io/pricing"),
            note: "Gladia shows usage in its app only. No billing API was found.", caps: []),
        ManualPreset(
            id: "hetzner", name: "Hetzner", billingURL: url("https://console.hetzner.com/"),
            docURL: url("https://docs.hetzner.com/cloud/billing/faq/"),
            note: "Hetzner Cloud's API has no billing or usage endpoint; invoices are in the console.", caps: []),
        ManualPreset(
            id: "ideogram", name: "Ideogram", billingURL: url("https://ideogram.ai/manage-api"),
            docURL: url("https://docs.ideogram.ai/"),
            note: "Ideogram's API balance and top-ups are in its dashboard only.", caps: []),
        ManualPreset(
            id: "instantly", name: "Instantly", billingURL: url("https://app.instantly.ai/"),
            docURL: url("https://instantly.ai/pricing"),
            note: "Instantly bills by plan. No billing or credit API was found.", caps: []),
        ManualPreset(
            id: "lambda", name: "Lambda", billingURL: url("https://cloud.lambda.ai/"),
            docURL: url("https://docs.lambda.ai/public-cloud/billing/"),
            note: "Lambda's Cloud API manages instances but has no billing endpoint.", caps: []),
        ManualPreset(
            id: "leonardo", name: "Leonardo.Ai", billingURL: url("https://app.leonardo.ai/settings"),
            docURL: url("https://docs.leonardo.ai/docs/getting-started"),
            note: "Leonardo's user endpoint reports token balances, but its reference page is gone, so Kill Cord "
                + "can't confirm the field names yet.", caps: []),
        ManualPreset(
            id: "linode", name: "Linode (Akamai Cloud)", billingURL: url("https://cloud.linode.com/account/billing"),
            docURL: url("https://techdocs.akamai.com/linode-api/reference/get-account"),
            note: "Linode's account API reports an estimated invoice with a read-only token; Kill Cord doesn't read "
                + "it yet.", caps: []),
        ManualPreset(
            id: "n8n", name: "n8n Cloud", billingURL: url("https://app.n8n.cloud/"),
            docURL: url("https://docs.n8n.io/manage-cloud/cloud-data-management/"),
            note: "n8n Cloud shows executions in its admin dashboard only.", caps: []),
        ManualPreset(
            id: "netlify", name: "Netlify", billingURL: url("https://app.netlify.com/"),
            docURL: url("https://docs.netlify.com/manage/accounts-and-billing/billing/billing-for-credit-based-plans/"
                + "monitor-usage-for-credit-based-plans/"),
            note: "Netlify shows credit usage in the app only.", caps: []),
        ManualPreset(
            id: "peopledatalabs", name: "People Data Labs", billingURL: url("https://dashboard.peopledatalabs.com/"),
            docURL: url("https://docs.peopledatalabs.com/docs/usage-limits"),
            note: "People Data Labs reports credits left only in headers on billable calls, so reading them would "
                + "cost credits.", caps: []),
        ManualPreset(
            id: "railway", name: "Railway", billingURL: url("https://railway.com/account/billing"),
            docURL: url("https://docs.railway.com/reference/usage-limits"),
            note: "Railway's API reports usage, but not clearly in dollars, and needs a token that can manage the "
                + "workspace.",
            caps: [
                cap("Railway", "hard-limit", "Usage hard limit",
                    "When usage reaches the hard limit, Railway takes all your workloads offline to stop further "
                        + "charges.",
                    .hardStop, console: "https://railway.com/workspace/usage",
                    doc: "https://docs.railway.com/reference/usage-limits",
                    steps: ["Open the Workspace Usage page.", "Click Set Usage Limits and set a hard limit."],
                    caveat: "Only a workspace admin can set it. A custom email alert is also offered; it only "
                        + "notifies.")
            ]),
        ManualPreset(
            id: "render", name: "Render", billingURL: url("https://dashboard.render.com/billing"),
            docURL: url("https://render.com/pricing"),
            note: "Render has no billing API; usage and invoices are in the dashboard.", caps: []),
        ManualPreset(
            id: "sambanova", name: "SambaNova Cloud", billingURL: url("https://cloud.sambanova.ai/"),
            docURL: url("https://cloud.sambanova.ai/plans"),
            note: "SambaNova Cloud shows usage in its console only. No billing API was found.", caps: []),
        ManualPreset(
            id: "serper", name: "Serper", billingURL: url("https://serper.dev/billing"),
            docURL: url("https://serper.dev/"),
            note: "Serper shows credits on its dashboard only. No balance API was found.", caps: []),
        ManualPreset(
            id: "vultr", name: "Vultr", billingURL: url("https://my.vultr.com/billing/"),
            docURL: url("https://docs.vultr.com/platform/billing/view-payment-history"),
            note: "Vultr's account API has a balance, but its docs don't say what the sign means, and its API keys "
                + "can do everything in the account.", caps: []),
        ManualPreset(
            id: "zapier", name: "Zapier", billingURL: url("https://zapier.com/app/settings/billing"),
            docURL: url("https://help.zapier.com/hc/en-us/articles/8496196837261"),
            note: "Zapier shows task usage in its settings only. No billing API was found.", caps: [])
    ]
}
