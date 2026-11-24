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
        )
    ]
}
