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
        )
    ]
}
