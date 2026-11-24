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
        )
    ]
}
