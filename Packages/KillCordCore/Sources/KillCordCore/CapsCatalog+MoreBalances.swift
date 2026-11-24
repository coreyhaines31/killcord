import Foundation

/// Native caps for the services in `ProviderInfo.moreBalanceProviders`. Same rules as `CapsCatalog`: each link
/// comes from the provider's docs.
extension CapsCatalog {
    private static func url(_ string: String) -> URL { URL(string: string)! }

    static let moreBalanceControls: [CapControl] = [
        // Runpod. https://docs.runpod.io/accounts-billing/billing
        CapControl(
            id: "runpod.prepaid-balance", provider: .runpod, name: "Prepaid balance, auto-pay off",
            summary: "When the balance reaches $0, Runpod stops all running Pods. With auto-pay off, nothing "
                + "tops it up.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://www.console.runpod.io/user/billing"),
            docURL: url("https://docs.runpod.io/accounts-billing/billing"),
            steps: ["Open Billing in the Runpod console.",
                    "Leave auto-pay off, or set a threshold and amount you accept."],
            caveat: "Network volume storage keeps billing while Pods are stopped. Post-paid accounts are invoiced, "
                + "so their balance stops nothing. Runpod also applies a spend limit of $80 an hour by default, "
                + "which only its support changes."
        ),
        CapControl(
            id: "runpod.low-balance", provider: .runpod, name: "Low balance notification",
            summary: "A daily email when the balance falls below a threshold you set.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://console.runpod.io/user/settings"),
            docURL: url("https://docs.runpod.io/accounts-billing/billing"),
            steps: ["Open Settings in the Runpod console.",
                    "Under Notification settings, edit General notifications.",
                    "Turn on Low balance notification and set the threshold in dollars."],
            caveat: nil
        ),
        // DeepInfra. https://docs.deepinfra.com/private-models/custom-llms and
        // https://docs.deepinfra.com/agents/introduction
        CapControl(
            id: "deepinfra.spending-limit", provider: .deepinfra, name: "Spending limit",
            summary: "DeepInfra tells you to set spending limits in its billing settings so a forgotten "
                + "deployment can't run up a bill.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://deepinfra.com/dash/billing"),
            docURL: url("https://docs.deepinfra.com/private-models/custom-llms"),
            steps: ["Open Billing in the DeepInfra dashboard.", "Set a spending limit you accept."],
            caveat: "DeepInfra's docs don't say exactly what stops at the limit. They do say a suspended account, "
                + "for example one whose balance ran out, has its instances stopped within a minute or two. An "
                + "API key can't change the limit, so Kill Cord can't check it."
        ),
        // X API. https://docs.x.com/x-api/getting-started/pricing
        CapControl(
            id: "xapi.spending-limit", provider: .xapi, name: "Spending limit per billing cycle",
            summary: "When the limit is reached, X blocks API requests until the next billing cycle.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.com"),
            docURL: url("https://docs.x.com/x-api/getting-started/pricing"),
            steps: ["Open billing in the X Developer Console.",
                    "Set a spending limit: the most you accept per billing cycle."],
            caveat: "Pay-per-use plans are also capped at 3 million Post reads per monthly billing cycle."
        ),
        CapControl(
            id: "xapi.prepaid-credits", provider: .xapi, name: "Prepaid credits, auto-recharge off",
            summary: "Requests are blocked when the credits run out. With auto-recharge off, nothing tops them up.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.x.com"),
            docURL: url("https://docs.x.com/x-api/getting-started/pricing"),
            steps: ["Open billing in the X Developer Console.",
                    "Leave auto-recharge off, or set a recharge amount and trigger you accept."],
            caveat: "The balance can go slightly negative before requests are blocked. Auto-recharge charges at "
                + "most once every 5 minutes."
        )
    ]
}
