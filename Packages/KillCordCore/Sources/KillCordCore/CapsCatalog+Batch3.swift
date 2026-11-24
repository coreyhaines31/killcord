import Foundation

/// Native caps for the services added in the third batch. Same rules as `CapsCatalog`: each link comes from
/// the provider's docs.
extension CapsCatalog {
    private static func url(_ string: String) -> URL { URL(string: string)! }

    static let batch3Controls: [CapControl] = [
        // Kimi. https://platform.kimi.ai/docs/guide/org-best-practice
        CapControl(
            id: "moonshot.project-budgets", provider: .moonshot, name: "Daily and monthly project budgets",
            summary: "When a project's spending reaches a budget you set, Kimi rejects that project's API requests "
                + "for the rest of the day or month.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://platform.kimi.ai/console"),
            docURL: url("https://platform.kimi.ai/docs/guide/org-best-practice"),
            steps: ["Pick the project from the menu at the top of the Kimi console.",
                    "Open Project Settings › Project Budget/Rate Limit Settings.",
                    "Set a daily and a monthly budget, then mark this done."],
            caveat: "Kimi says enforcement may be delayed, and spending during the delay is still billed. Each "
                + "project needs its own budget."
        ),
        // Kimi. https://platform.kimi.ai/docs/api/balance
        CapControl(
            id: "moonshot.balance", provider: .moonshot, name: "Prepaid balance",
            summary: "When the available balance reaches zero, Kimi refuses inference calls until you add funds.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://platform.kimi.ai/console"),
            docURL: url("https://platform.kimi.ai/docs/api/balance"),
            steps: ["Add only as much as you're willing to spend, then mark this done."],
            caveat: "There's nothing to switch on: the balance is the cap. Vouchers count toward it too."
        ),
        // Exa. https://exa.ai/docs/admin/billing
        CapControl(
            id: "exa.key-budget", provider: .exa, name: "Budget on each API key",
            summary: "An API key that reaches its budget gets 402 Payment Required until the next billing period "
                + "or until an administrator raises it.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.exa.ai/api-keys"),
            docURL: url("https://exa.ai/docs/admin/billing"),
            steps: ["Open API Keys in the Exa dashboard.",
                    "Give each key your apps use a budget, then mark this done."],
            caveat: "A budget covers one key. Keys without one draw on the team's credits until they run out."
        ),
        CapControl(
            id: "exa.auto-recharge", provider: .exa, name: "Auto recharge off, or a monthly maximum",
            summary: "With auto recharge off, requests return 402 when the team's credits reach zero. With it on, "
                + "the monthly maximum caps automatic purchases each billing cycle.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.exa.ai/billing"),
            docURL: url("https://exa.ai/docs/admin/billing"),
            steps: ["Open Billing in the Exa dashboard.",
                    "Leave auto recharge off, or set a monthly maximum above $0."],
            caveat: "A monthly maximum of $0, or a blank one, means no cap on automatic purchases. A team with "
                + "overage turned on keeps running past zero."
        ),
        // ScrapingBee. https://help.scrapingbee.com/en/article/auto-renewal-f79j19/
        CapControl(
            id: "scrapingbee.auto-renew", provider: .scrapingbee, name: "Auto renew off",
            summary: "With auto renew on, ScrapingBee renews your subscription, and charges for it, once 98% of "
                + "your credits are used. With it off, requests stop when the credits run out.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.scrapingbee.com/account/manage/manage_subscription"),
            docURL: url("https://help.scrapingbee.com/en/article/auto-renewal-f79j19/"),
            steps: ["Open Manage subscription in the ScrapingBee dashboard.",
                    "Leave auto renew off, then mark this done."],
            caveat: "Auto renew also moves your renewal date. ScrapingBee documents no spend limit or alert."
        ),
        // Scrapfly. https://scrapfly.io/docs/project and https://scrapfly.io/docs/billing
        CapControl(
            id: "scrapfly.extra-usage", provider: .scrapfly, name: "No extra credit use on each project",
            summary: "With extra use off, a project's calls past its quota are refused instead of billed as extra "
                + "credits.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://scrapfly.io/dashboard/project"),
            docURL: url("https://scrapfly.io/docs/billing"),
            steps: ["Open Projects in the Scrapfly dashboard and edit each project.",
                    "Uncheck Allow PAG, or keep it and set the project's Budget Limit, then mark this done."],
            caveat: "Each project has its own settings. Paid plans also cap extra use at 50% of the monthly quota by "
                + "default, then suspend the account."
        ),
        // Kie.ai. https://docs.kie.ai/getting-started
        CapControl(
            id: "kie.key-caps", provider: .kie, name: "Usage caps on each API key",
            summary: "Each key can carry hourly, daily and total usage caps.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://kie.ai/api-key"),
            docURL: url("https://docs.kie.ai/getting-started"),
            steps: ["Open API Key on kie.ai.", "Set hourly, daily and total caps on each key your apps use."],
            caveat: "Kie.ai's docs don't say what happens when a key reaches a cap, so don't count on it to stop "
                + "usage. Running out of credits does: services stop until you add more."
        ),
        // Bland. https://docs.bland.ai/platform/billing
        CapControl(
            id: "bland.credits", provider: .bland, name: "Prepaid credits, auto refill off",
            summary: "Bland bills calls, SMS and voice from prepaid credits. With auto refill off, usage stops when "
                + "the credits run out.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.bland.ai/dashboard/pay"),
            docURL: url("https://docs.bland.ai/platform/billing"),
            steps: ["Open Billing & Credits in the Bland dashboard.",
                    "Leave auto refill off, or set a refill you accept, then mark this done."],
            caveat: "Bland says usage can pass zero before it stops, leaving a negative balance."
        ),
        // LlamaCloud. https://developers.llamaindex.ai/llamaparse/general/billing/
        CapControl(
            id: LlamaCloudProvider.spendLimitCapID, provider: .llamacloud, name: "Monthly invoice limit",
            summary: "When the organization's invoice reaches its monthly limit, LlamaCloud refuses new jobs until "
                + "the next billing period.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://cloud.llamaindex.ai"),
            docURL: url("https://admin.api.llamaindex.ai/api/resources/organizations/methods/get_usage"),
            steps: ["Open Settings › Organization › Plan & Credits in LlamaCloud.",
                    "Set a monthly spending limit if your plan offers one."],
            caveat: "Kill Cord reads the limit and whether it's been reached from LlamaCloud's usage API."
        ),
        CapControl(
            id: "llamacloud.pause-jobs", provider: .llamacloud, name: "Pause jobs when credits run out",
            summary: "With Pause jobs chosen, new jobs stop when the credit balance reaches zero and return a 402 "
                + "error. Jobs already running finish.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://cloud.llamaindex.ai"),
            docURL: url("https://developers.llamaindex.ai/llamaparse/general/billing/"),
            steps: ["Open Settings › Organization › Plan & Credits in LlamaCloud.",
                    "Under When credits run out, choose Pause jobs, or Reload credits automatically with a monthly "
                        + "cap you accept."],
            caveat: "If Keep going, bill me for extra usage is chosen, jobs keep starting past zero, and on Starter "
                + "that has no monthly cap. LlamaCloud doesn't let you choose it again once it's off."
        ),
        // Cartesia. https://docs.cartesia.ai/pricing
        CapControl(
            id: "cartesia.overages-off", provider: .cartesia, name: "Overages off",
            summary: "With overages disabled, requests that would exceed your plan's credits fail until the plan "
                + "renews or you upgrade.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://play.cartesia.ai/subscription"),
            docURL: url("https://docs.cartesia.ai/pricing"),
            steps: ["Open Subscription in the Cartesia playground.", "Leave overages off, then mark this done."],
            caveat: "With overages on, the balance can go negative and keeps billing."
        ),
        // Together AI. https://docs.together.ai/docs/billing-spend-controls
        CapControl(
            id: "together.zero-balance", provider: .together, name: "Prepaid balance, auto-recharge off",
            summary: "API access stops when the organization's balance reaches zero. Auto-recharge tops it up and "
                + "doesn't cap spend.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://api.together.ai/settings/organization/~current/billing"),
            docURL: url("https://docs.together.ai/docs/billing-spend-controls"),
            steps: ["Open Billing in Together's organization settings.",
                    "Leave auto-recharge off, and buy only the credits you're willing to spend."],
            caveat: "Together says this \"does not guarantee an exact spending cap\". Budgets and spend alerts "
                + "aren't available yet, and keys can't have their own limits."
        ),
        // Fireworks AI. https://docs.fireworks.ai/guides/quotas_usage/account-quotas
        CapControl(
            id: FireworksProvider.spendLimitCapID, provider: .fireworks, name: "Monthly spend limit",
            summary: "When usage reaches 100% of the limit, Fireworks pauses all API requests across serverless "
                + "inference, deployments, and training. It emails a warning at 80%.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://fireworks.ai/billing"),
            docURL: url("https://docs.fireworks.ai/guides/quotas_usage/account-quotas"),
            steps: ["Set the limit with firectl: firectl quota update monthly-spend-usd --value <amount>.",
                    "Add notification amounts on the Billing page if you want more warnings."],
            caveat: "Kill Cord reads the monthly-spend-usd quota from Fireworks' API. Enterprise accounts get "
                + "alerts only."
        ),
        // Vapi. https://docs.vapi.ai/billing/manage-billing-and-credits
        CapControl(
            id: "vapi.credits", provider: .vapi, name: "Prepaid credits, auto-reload off",
            summary: "With auto-reload off, Vapi freezes the subscription when its credit balance reaches $0: no new "
                + "calls or other billable usage until you buy more.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.vapi.ai"),
            docURL: url("https://docs.vapi.ai/billing/manage-billing-and-credits"),
            steps: ["Open Billing in the Vapi dashboard.",
                    "Leave auto-reload off, or set a threshold and top-up you accept."],
            caveat: "Vapi documents no spend limit you set yourself. With auto-reload on, it buys credits every "
                + "time the balance reaches your threshold."
        ),
        // Retell AI. https://docs.retellai.com/accounts/billing
        CapControl(
            id: "retell.monthly-budget", provider: .retell, name: "Monthly budget",
            summary: "At 100% of the budget, Retell pauses calls and API requests until the next calendar month "
                + "(UTC), even with credits left. It emails at 80% and 100%.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.retellai.com"),
            docURL: url("https://docs.retellai.com/accounts/billing"),
            steps: ["Open Billing in the Retell dashboard.", "Set a monthly budget, from $10 to $100,000."],
            caveat: "Workspaces without the budget button have no monthly cap. While it's paused, Kill Cord can't "
                + "read the call list either."
        ),
        CapControl(
            id: "retell.auto-recharge", provider: .retell, name: "Auto recharge off",
            summary: "With auto recharge off, calls, chat and other usage stop when the credits reach $0, until you "
                + "buy more.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://dashboard.retellai.com"),
            docURL: url("https://docs.retellai.com/accounts/billing"),
            steps: ["Open Billing in the Retell dashboard.", "Leave auto recharge off, or set a refill you accept."],
            caveat: nil
        ),
        // Browserbase. https://docs.browserbase.com/account/billing/plans
        CapControl(
            id: "browserbase.allocations", provider: .browserbase, name: "Plan allocations, watched by hand",
            summary: "Plans include browser hours and proxy data. Usage past them is billed as overage, and "
                + "nothing stops it.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://www.browserbase.com/settings"),
            docURL: url("https://docs.browserbase.com/account/billing/plans"),
            steps: ["Open Settings › Usage & billing in Browserbase.",
                    "Check your plan's hours and proxy data against the usage Kill Cord shows."],
            caveat: "Browserbase has no native hard spend cap: its docs call the allocations \"not limits\", with "
                + "\"No caps. No cut-offs.\" Only concurrency is limited."
        ),
        // Resend. https://resend.com/docs/knowledge-base/account-quotas-and-limits
        CapControl(
            id: "resend.overages-off", provider: .resend, name: "Overages off, or an overage limit",
            summary: "With overages off, the default, sending stops at your monthly quota until the next billing "
                + "cycle. With them on, sending pauses at the overage limit.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://resend.com/settings/usage"),
            docURL: url("https://resend.com/docs/knowledge-base/account-quotas-and-limits"),
            steps: ["Open Settings › Usage in Resend.",
                    "Leave overages off, or set the overage limit you accept (100% to 1,000% of the plan)."],
            caveat: "The overage limit defaults to 400% of the plan's quota when overages are on."
        ),
        // Postmark. https://postmarkapp.com/support/article/1285-pricing-billing-faq
        CapControl(
            id: "postmark.no-cap", provider: .postmark, name: "Plan emails, watched by hand",
            summary: "Postmark keeps sending past your plan's emails and bills the extra as overage. It emails you "
                + "when the plan's emails are used up.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://account.postmarkapp.com/servers"),
            docURL: url("https://postmarkapp.com/support/article/1285-pricing-billing-faq"),
            steps: ["Check the sent counts Kill Cord shows against your plan.",
                    "Watch for Postmark's \"You've used all your Postmark emails\" email."],
            caveat: "Postmark has no native hard spend cap: \"it is not possible to disable the sending of "
                + "Additional emails or set up any limits to your sending.\" The Free plan allows no overage."
        ),
        // Mistral. https://docs.mistral.ai/admin/billing-usage/usage-limits
        CapControl(
            id: MistralProvider.spendLimitCapID, provider: .mistral, name: "Organization monthly spending limit",
            summary: "If the Organization reaches its monthly spending limit, Mistral can suspend API access until "
                + "the next month or until an admin raises the limit.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://admin.mistral.ai/organization/billing"),
            docURL: url("https://docs.mistral.ai/admin/billing-usage/usage-limits"),
            steps: ["Open Subscriptions › Billing in the Mistral Admin Panel.", "Set a monthly spending limit."],
            caveat: "Kill Cord reads the limit and whether it's reached from the Admin API. Mistral says access "
                + "\"can be\" suspended, not that it always is."
        ),
        CapControl(
            id: "mistral.workspace-limits", provider: .mistral, name: "Workspace spending limits",
            summary: "Each Workspace can have its own spending cap, so one app can't use the Organization's whole "
                + "budget.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://admin.mistral.ai/organization/workspaces"),
            docURL: url("https://docs.mistral.ai/admin/billing-usage/usage-limits"),
            steps: ["Open Administration › Workspaces in the Mistral Admin Panel.",
                    "Set a spending limit on each Workspace your apps use."],
            caveat: nil
        ),
        // Hugging Face. https://huggingface.co/docs/inference-providers/pricing
        CapControl(
            id: "huggingface.org-spending-limit", provider: .huggingface, name: "Organization spending limit",
            summary: "Team and Enterprise administrators can set a spending limit for Inference Providers usage "
                + "billed to the organization.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://huggingface.co/settings/billing"),
            docURL: url("https://huggingface.co/docs/inference-providers/pricing"),
            steps: ["Open the organization's settings on Hugging Face.",
                    "Set an Inference Providers spending limit, then mark this done."],
            caveat: "Hugging Face's docs don't say exactly what happens at the limit, so check that requests "
                + "stop. It covers usage billed to the organization, not members' own accounts."
        ),
        // Magister. https://magistermarketing.com/docs/api/credits-and-billing
        CapControl(
            id: "magister.auto-recharge", provider: .magister, name: "Auto-recharge off, or a monthly limit",
            summary: "Requests the API credit balance can't cover are refused with a 402 before any work starts. "
                + "Auto-recharge tops the balance up, at most your monthly limit.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://magistermarketing.com/developers/billing"),
            docURL: url("https://magistermarketing.com/docs/api/credits-and-billing"),
            steps: ["Open API billing in Magister.",
                    "Leave auto-recharge off, or set a monthly limit you accept."],
            caveat: "Each key can also carry a daily credit cap, set when it's created."
        ),
        CapControl(
            id: "magister.low-balance", provider: .magister, name: "Low-balance alert",
            summary: "Magister emails owners and admins once each time the API credit balance falls below your "
                + "threshold (1,000 credits unless you change it).",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://magistermarketing.com/developers/billing"),
            docURL: url("https://magistermarketing.com/docs/api/credits-and-billing"),
            steps: ["Open API billing in Magister.", "Set the low-balance alert threshold."],
            caveat: "It only notifies. Nothing stops."
        )
    ]
}
