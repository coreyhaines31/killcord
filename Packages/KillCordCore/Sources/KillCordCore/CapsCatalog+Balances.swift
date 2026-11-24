import Foundation

/// Native caps for the services Kill Cord reads a balance or allowance from. Same rules as `CapsCatalog`: each
/// link comes from the provider's docs.
extension CapsCatalog {
    private static func url(_ string: String) -> URL { URL(string: string)! }

    static let balanceControls: [CapControl] = [
        // OpenRouter. https://openrouter.ai/docs/api-reference/limits
        CapControl(
            id: "openrouter.key-limit", provider: .openrouter, name: "Credit limit on each key",
            summary: "A key with a credit limit stops working once it has spent that much. Keys with no limit "
                + "can spend the whole balance.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://openrouter.ai/settings/keys"),
            docURL: url("https://openrouter.ai/docs/api-reference/limits"),
            steps: ["Open Settings › API Keys.", "Edit each key your apps use and give it a credit limit."],
            caveat: "Kill Cord reads the limit of the key you connect, not the others."
        ),
        // Monid. https://monid.ai/SKILL.md
        CapControl(
            id: "monid.workspace-budget", provider: .monid, name: "Workspace budget and run caps",
            summary: "Monid blocks a run that would go past a workspace budget or run cap.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.monid.ai/"),
            docURL: url("https://monid.ai/SKILL.md"),
            steps: ["Open the Monid dashboard.", "Set a workspace budget or run cap."],
            caveat: "Monid's public docs mention these settings but don't describe them in detail."
        ),
        // fal. https://fal.ai/docs/documentation/model-apis/faq
        CapControl(
            id: "fal.balance-lock", provider: .fal, name: "Prepaid credits lock",
            summary: "When the credit balance drops below the account's lock threshold, fal locks the account and "
                + "rejects API requests.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://fal.ai/dashboard/billing"),
            docURL: url("https://fal.ai/docs/documentation/model-apis/faq"),
            steps: ["Open Billing in the fal dashboard.",
                    "Buy only as many credits as you're willing to spend, then mark this done."],
            caveat: "There's nothing to switch on: the balance is the cap. fal doesn't document a spend limit you "
                + "set yourself."
        )
    ]
}
