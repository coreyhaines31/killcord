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
        )
    ]
}
