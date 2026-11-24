import Foundation

/// A paid service Kill Cord knows has no billing API, ready to start a manual entry from: its name, its
/// billing page, and its own spend controls for the caps audit. Each link comes from the service's docs
/// (`docURL`), checked 2026-11-24. Picking one only fills in the name; the plan is still typed in by hand.
public struct ManualPreset: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    /// Where the service shows the balance or bill, to copy the plan from.
    public let billingURL: URL
    /// The docs page that says what billing and controls the service has.
    public let docURL: URL
    /// What the service offers in place of a billing API, in a sentence.
    public let note: String
    /// The service's own spend controls. Never checked by Kill Cord: there's no API.
    public let caps: [CapControl]

    /// The preset a manual entry is named after, if any. Case and spaces don't matter.
    public static func matching(_ serviceName: String?) -> ManualPreset? {
        guard let key = serviceName.map(normalized), !key.isEmpty else { return nil }
        return all.first { normalized($0.name) == key || normalized($0.id) == key }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

extension CapsCatalog {
    /// A provider's caps. Manual entries named after a preset get that preset's caps.
    public static func controls(for provider: ProviderID, manualServices: [String]) -> [CapControl] {
        guard provider == .manual else { return controls(for: provider) }
        var seen: Set<String> = []
        return manualServices.compactMap(ManualPreset.matching).filter { seen.insert($0.id).inserted }
            .flatMap(\.caps)
    }
}

extension CapAuditState {
    /// Progress over any list of caps, such as one manual entry's preset.
    public func progress(of controls: [CapControl], now: Date) -> Progress {
        let statuses = controls.map { status(of: $0, now: now) }
        return Progress(done: statuses.filter(\.isDone).count, total: statuses.count,
                        needsAttention: statuses.filter(\.needsAttention).count)
    }
}

extension ManualPreset {
    static func url(_ string: String) -> URL { URL(string: string)! }

    // The same fields as CapControl's, with the provider and verification every preset cap shares.
    // swiftlint:disable:next function_parameter_count
    static func cap(_ preset: String, _ id: String, _ name: String, _ summary: String,
                    _ enforcement: CapControl.Enforcement, console: String, doc: String,
                    steps: [String], caveat: String?) -> CapControl {
        // Named with the service, since Caps Audit lists every manual entry's caps together.
        CapControl(id: "manual.\(ManualPreset.normalized(preset)).\(id)", provider: .manual,
                   name: "\(preset): \(name)", summary: summary,
                   enforcement: enforcement, verification: .selfReported, consoleURL: url(console),
                   docURL: url(doc), steps: steps, caveat: caveat)
    }

    /// Alphabetical, the order the picker lists them.
    public static let all: [ManualPreset] = (corePresets + morePresets)
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static let corePresets: [ManualPreset] = [
        ManualPreset(
            id: "assemblyai", name: "AssemblyAI", billingURL: url("https://www.assemblyai.com/dashboard/home"),
            docURL: url("https://www.assemblyai.com/docs/account-management"),
            note: "AssemblyAI shows its balance on the dashboard only.",
            caps: [
                cap("AssemblyAI", "balance", "Prepaid balance, auto-pay off",
                    "Without auto-pay, API access pauses when the balance reaches $0, until you top up.",
                    .hardStop, console: "https://www.assemblyai.com/dashboard/home",
                    doc: "https://www.assemblyai.com/docs/account-management",
                    steps: ["Open Workspace › Settings › Billing.", "Leave auto-pay off, or set a refill you accept."],
                    caveat: nil),
                cap("AssemblyAI", "alerts", "Usage and balance alerts",
                    "Emails when usage or the balance crosses an amount you set.",
                    .alertOnly, console: "https://www.assemblyai.com/dashboard/home",
                    doc: "https://www.assemblyai.com/docs/account-management",
                    steps: ["Open Workspace › Settings › Alerts.", "Add a balance alert and a usage alert."],
                    caveat: "It only notifies. Nothing stops.")
            ]),
        ManualPreset(
            id: "cerebras", name: "Cerebras", billingURL: url("https://cloud.cerebras.ai"),
            docURL: url("https://inference-docs.cerebras.ai/console/account-billing"),
            note: "Cerebras shows its credit balance in the console, with a CSV export.",
            caps: [
                cap("Cerebras", "auto-recharge", "Auto-recharge off",
                    "Cerebras runs on prepaid credits. Auto-recharge is off by default; with it off, nothing tops "
                        + "the credits up for you.",
                    .alertOnly, console: "https://cloud.cerebras.ai",
                    doc: "https://inference-docs.cerebras.ai/console/account-billing",
                    steps: ["Open Billing in the Cerebras console.", "Check that auto-recharge is off."],
                    caveat: "Cerebras documents no spend limit, and its docs don't say what happens when credits "
                        + "run out, so this is marked alert only.")
            ]),
        ManualPreset(
            id: "cohere", name: "Cohere", billingURL: url("https://dashboard.cohere.com"),
            docURL: url("https://docs.cohere.com/docs/going-live"),
            note: "Cohere reports billed units per request but has no billing API. Its docs describe no spend "
                + "cap.",
            caps: []),
        ManualPreset(
            id: "e2b", name: "E2B", billingURL: url("https://console.e2b.dev/?tab=billing"),
            docURL: url("https://e2b.dev/docs/billing"),
            note: "E2B shows usage on its console's Usage page.",
            caps: [
                cap("E2B", "spending-limit", "Spending limit",
                    "E2B lets you set spending limits on the console's Limits page.",
                    .alertOnly, console: "https://console.e2b.dev/?tab=limits", doc: "https://e2b.dev/docs/billing",
                    steps: ["Open Limits in the E2B console.", "Set a spending limit."],
                    caveat: "E2B's docs don't say whether usage stops at the limit, so don't count on it to.")
            ]),
        ManualPreset(
            id: "groq", name: "Groq", billingURL: url("https://console.groq.com/settings/billing"),
            docURL: url("https://console.groq.com/docs/spend-limits"),
            note: "Groq shows spend in its console only.",
            caps: [
                cap("Groq", "spend-limit", "Monthly spend limit",
                    "Past the limit, API calls from every key in the organization are refused until the 1st.",
                    .hardStop, console: "https://console.groq.com/settings/billing/limits",
                    doc: "https://console.groq.com/docs/spend-limits",
                    steps: ["Open Settings › Billing › Limits in the Groq console.", "Set a monthly spend limit."],
                    caveat: "Paid tier, organization owners only. Groq's spend tracking runs 10 to 15 minutes "
                        + "behind, so it can pass the limit by a little."),
                cap("Groq", "spend-alerts", "Spend alerts",
                    "Emails at amounts you choose.",
                    .alertOnly, console: "https://console.groq.com/settings/billing/limits",
                    doc: "https://console.groq.com/docs/spend-limits",
                    steps: ["On the same Limits page, add alert amounts."],
                    caveat: "It only notifies. Nothing stops.")
            ]),
        ManualPreset(
            id: "jina", name: "Jina AI", billingURL: url("https://jina.ai/api-dashboard/"),
            docURL: url("https://jina.ai/api-dashboard/"),
            note: "Jina keeps a token balance on each API key, shown on its dashboard only.",
            caps: []),
        ManualPreset(
            id: "perplexity", name: "Perplexity", billingURL: url("https://console.perplexity.ai/project/billing"),
            docURL: url("https://docs.perplexity.ai/docs/getting-started/projects"),
            note: "Perplexity's API runs on prepaid credits shown in its console only.",
            caps: [
                cap("Perplexity", "credits", "Prepaid credits, auto reload off",
                    "When the credits run out, Perplexity blocks your API keys until you add more.",
                    .hardStop, console: "https://console.perplexity.ai/project/billing",
                    doc: "https://docs.perplexity.ai/docs/getting-started/projects",
                    steps: ["Open Billing in the Perplexity console.", "Leave auto reload off, or set an amount you "
                        + "accept."],
                    caveat: "Perplexity documents no spend limit beyond the credits.")
            ]),
        ManualPreset(
            id: "replicate", name: "Replicate", billingURL: url("https://replicate.com/account/billing"),
            docURL: url("https://replicate.com/docs/topics/billing/prepaid-credit"),
            note: "Replicate's account API has no billing data.",
            caps: [
                cap("Replicate", "prepaid", "Prepaid credit, auto reload off",
                    "When a prepaid balance hits zero, Replicate stops new work from starting and shuts down "
                        + "what it's running for you.",
                    .hardStop, console: "https://replicate.com/account/billing",
                    doc: "https://replicate.com/docs/topics/billing/prepaid-credit",
                    steps: ["Open Billing on Replicate.", "Use prepaid credit and leave auto reload off, or set "
                        + "amounts you accept."],
                    caveat: "Replicate retired its monthly spend limit in 2025. Accounts billed in arrears have no "
                        + "cap.")
            ]),
        ManualPreset(
            id: "twelvelabs", name: "Twelve Labs", billingURL: url("https://playground.twelvelabs.io"),
            docURL: url("https://docs.twelvelabs.io/docs/get-started/plans-and-billing/plans-allowances-and-overage"),
            note: "Twelve Labs shows plans and usage in its Playground settings.",
            caps: [
                cap("Twelve Labs", "overage-off", "Overage off",
                    "With overage off, requests fail once you reach the plan's allowance.",
                    .hardStop, console: "https://playground.twelvelabs.io",
                    doc: "https://docs.twelvelabs.io/docs/get-started/plans-and-billing/plans-allowances-and-overage",
                    steps: ["Open Settings › Billing & Plans in the Playground.", "Check that overage is off."],
                    caveat: "Overage is off by default on Pro and on by default on Enterprise.")
            ]),
        ManualPreset(
            id: "typesafe", name: "TypeSafe Jev", billingURL: url("https://console.typesafe.ai/"),
            docURL: url("https://docs.typesafe.ai/pricing"),
            note: "TypeSafe's API (jev-latest) reports tokens per response, and its docs describe no billing "
                + "endpoint or spend cap.",
            caps: []),
        ManualPreset(
            id: "unstructured", name: "Unstructured", billingURL: url("https://transform.unstructured.io"),
            docURL: url("https://docs.unstructured.io/transform/billing"),
            note: "Unstructured shows its prepaid balance on the Billing page only.",
            caps: [
                cap("Unstructured", "prepaid", "Prepaid balance",
                    "Each job's cost is reserved first. If the balance can't cover it, the request fails before "
                        + "a job starts.",
                    .hardStop, console: "https://transform.unstructured.io",
                    doc: "https://docs.unstructured.io/transform/billing",
                    steps: ["Open Billing.", "Add only what you're willing to spend, then mark this done."],
                    caveat: "There's no auto top-up to turn off. The balance expires 12 months after your last "
                        + "payment.")
            ]),
        ManualPreset(
            id: "voyage", name: "Voyage AI", billingURL: url("https://cloud.mongodb.com/"),
            docURL: url("https://www.mongodb.com/docs/voyageai/management/billing/"),
            note: "Voyage AI bills through MongoDB Atlas, where usage shows in the Atlas billing pages. Its docs "
                + "describe no spend cap.",
            caps: [])
    ]
}
