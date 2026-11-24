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
        ),
        // ElevenLabs. https://elevenlabs.io/docs/overview/administration/workspaces/api-keys
        CapControl(
            id: "elevenlabs.key-quota", provider: .elevenlabs, name: "Credit quota on each key",
            summary: "A key with a credit quota stops working for anything that costs credits once it reaches "
                + "that monthly limit.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://elevenlabs.io/app/settings/api-keys"),
            docURL: url("https://elevenlabs.io/docs/overview/administration/workspaces/api-keys"),
            steps: ["Open Settings › API Keys.", "Edit each key your apps use and set a credit quota."],
            caveat: "Keys with no quota can use the whole plan, and pay-as-you-go credits too."
        ),
        CapControl(
            id: "elevenlabs.usage-notification", provider: .elevenlabs, name: "Credit usage notification",
            summary: "An email when you've used a share of your credits.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://elevenlabs.io/app/subscription"),
            docURL: url("https://elevenlabs.io/docs/help-center/account/general/"
                + "can-i-be-notified-when-im-running-low-on-credits"),
            steps: ["Open Subscription.", "Turn on the credit usage notification and pick the percentage."],
            caveat: "It only notifies. Nothing stops."
        ),
        // xAI. https://docs.x.ai/console/billing
        CapControl(
            id: "xai.invoiced-limit", provider: .xai, name: "Invoiced billing limit at $0",
            summary: "With a $0 invoiced billing limit (the default), xAI uses only your prepaid credits and rejects "
                + "API requests once they run out.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.ai/team/default/billing"),
            docURL: url("https://docs.x.ai/console/billing"),
            steps: ["Open Billing in the xAI Console.",
                    "Check that monthly invoiced billing is off, or its limit is $0 or an amount you accept."],
            caveat: "Above $0, requests keep working until the month's invoiced amount reaches the limit."
        ),
        CapControl(
            id: "xai.auto-topup-max", provider: .xai, name: "Auto top-up monthly maximum",
            summary: "If auto top-up is on, a monthly maximum caps how much it can buy for you.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.ai/team/default/billing"),
            docURL: url("https://docs.x.ai/console/billing"),
            steps: ["Open Billing in the xAI Console.",
                    "Turn auto top-up off, or set its maximum total of top-ups per month."],
            caveat: "It stops spend only while the invoiced billing limit is $0."
        ),
        // Apify. https://docs.apify.com/platform/console/billing
        CapControl(
            id: ApifyProvider.usageLimitCapID, provider: .apify, name: "Usage limit",
            summary: "How much the account can spend in a usage cycle. Once it's reached, Apify suspends its "
                + "services to protect you against unwanted charges.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://console.apify.com/billing#/limits"),
            docURL: url("https://docs.apify.com/platform/console/billing"),
            steps: ["Open Billing › Limits in Apify Console.",
                    "Under Custom usage limit, choose Edit limit and set the most you'll spend in a cycle."],
            caveat: "By default the limit matches your plan's prepaid usage. Custom limits top out at $100 on "
                + "Starter, $1,000 on Scale and $5,000 on Business."
        ),
        // Tavily. https://docs.tavily.com/documentation/platform/managing-organizations
        CapControl(
            id: "tavily.workspace-limit", provider: .tavily, name: "Workspace credit limit",
            summary: "A ceiling on the credits a workspace can spend. Every request is checked against it and "
                + "the plan limit, and whichever is reached first refuses it.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.tavily.com"),
            docURL: url("https://docs.tavily.com/documentation/platform/managing-organizations"),
            steps: ["On the Overview page, choose Set a limit on the Workspace Usage card.",
                    "Enter a number of credits. An organization owner or admin can set it."],
            caveat: "Tavily says enforcement is approximate: requests already in flight can carry a workspace "
                + "slightly past its limit. Refusals arrive as HTTP 432."
        ),
        CapControl(
            id: "tavily.key-limit", provider: .tavily, name: "Credit limit on each key",
            summary: "A key with a credit limit is refused once it has used that many credits.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://app.tavily.com"),
            docURL: url("https://docs.tavily.com/documentation/platform/managing-organizations"),
            steps: ["On the Overview page, edit each key your apps use.", "Give it a credit limit."],
            caveat: "Tavily says enforcement is approximate, as for workspace limits."
        )
    ]
}
