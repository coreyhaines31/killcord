import Foundation

/// A provider's own spend control: what it's called, what it does, and where to turn it on.
public struct CapControl: Sendable, Identifiable, Equatable {
    public enum Enforcement: String, Sendable, Codable {
        /// Usage stops when the cap is reached. Providers note it isn't instant.
        case hardStop
        /// Some usage stops, some keeps billing (Vercel pauses deployments, not storage).
        case partialStop
        /// It notifies. Nothing stops.
        case alertOnly

        public var label: String {
            switch self {
            case .hardStop: "Hard stop"
            case .partialStop: "Partial stop"
            case .alertOnly: "Alert only"
            }
        }
    }

    public enum Verification: String, Sendable, Codable {
        /// Kill Cord can read this setting from the provider's API.
        case api
        /// No API exposes it: the audit trusts what the person marks.
        case selfReported
    }

    public let id: String
    public let provider: ProviderID
    public let name: String
    public let summary: String
    public let enforcement: Enforcement
    public let verification: Verification
    /// The console page where the setting lives.
    public let consoleURL: URL
    /// The provider's docs for it.
    public let docURL: URL
    public let steps: [String]
    /// Limits worth knowing before relying on it.
    public let caveat: String?
}

/// Every native cap Kill Cord walks through, verified against each provider's docs (links in `docURL`).
/// Console links are the ones those docs use; where a provider has no stable deep link, the link opens the
/// console and the steps say where to go.
public enum CapsCatalog {
    private static func url(_ string: String) -> URL { URL(string: string)! }

    public static let controls: [CapControl] = [
        // Anthropic. https://platform.claude.com/docs/en/api/rate-limits
        CapControl(
            id: "anthropic.org-spend-limit", provider: .anthropic, name: "Organization spend limit",
            summary: "A monthly dollar limit for the whole organization. Past it, API requests fail until the next "
                + "month or until you raise it.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://platform.claude.com/settings/spend-limits"),
            docURL: url("https://platform.claude.com/docs/en/api/rate-limits"),
            steps: ["Open Settings › Spend limits in the Claude Console.",
                    "Set a monthly limit for the organization below your tier's limit.",
                    "Save, then mark this done."],
            caveat: "Anthropic's API can't read this setting for Console organizations, so Kill Cord trusts your "
                + "mark. Re-check it now and then."
        ),
        CapControl(
            id: "anthropic.workspace-limit", provider: .anthropic, name: "Workspace spend limit",
            summary: "Put production keys in their own workspace with its own monthly limit, so one runaway "
                + "app can't use the whole organization's budget.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://platform.claude.com/settings/workspaces"),
            docURL: url("https://platform.claude.com/docs/en/manage-claude/workspaces"),
            steps: ["Create a workspace for each app or environment under Settings › Workspaces.",
                    "Move that app's API keys into it.",
                    "Under Settings › Spend limits, pick the workspace and set its limit."],
            caveat: "The Default Workspace can't have a spend limit, which is why keys belong in another one."
        ),
        // Google Cloud and Gemini.
        CapControl(
            id: GoogleCloudProvider.spendCapID, provider: .google, name: "Spend cap budget",
            summary: "A monthly budget for one project and one service (Gemini API, Vertex AI, or Cloud Run) that "
                + "pauses that service when estimated spend passes it.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://console.cloud.google.com/billing/budgets"),
            docURL: url("https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps"),
            steps: ["Open Billing › Budgets & alerts and create a budget.",
                    "Scope it to one project and one service, such as the Gemini API.",
                    "Turn on the spend cap, set the monthly amount, and save."],
            caveat: "Google says enforcement isn't instant and overages are billed. Add your billing account ID "
                + "in Settings › Providers so Kill Cord can check it."
        ),
        CapControl(
            id: "google.aistudio-project-cap", provider: .google, name: "AI Studio project spend cap",
            summary: "A monthly cap for a Gemini API project, set in Google AI Studio.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://aistudio.google.com/spend"),
            docURL: url("https://aistudio.google.com/docs/billing"),
            steps: ["Open the Spend page in Google AI Studio and pick the project.",
                    "Set a Monthly spend cap and save."],
            caveat: "Google calls this experimental: it can lag about 10 minutes, and batch work can overshoot. "
                + "The spend cap budget above is the sturdier control."
        ),
        CapControl(
            id: GoogleCloudProvider.budgetAlertCapID, provider: .google, name: "Budget alerts",
            summary: "A budget that emails billing admins at thresholds you choose, across any projects and "
                + "services.",
            enforcement: .alertOnly, verification: .api,
            consoleURL: url("https://console.cloud.google.com/billing/budgets"),
            docURL: url("https://docs.cloud.google.com/billing/docs/how-to/budgets"),
            steps: ["Open Billing › Budgets & alerts and create a budget for the billing account.",
                    "Set thresholds, for example 50%, 90%, and 100%, and save."],
            caveat: "Google: an alerts-only budget doesn't cap usage or spending."
        ),
        // OpenAI. https://developers.openai.com/api/docs/guides/spend-limits
        CapControl(
            id: OpenAIProvider.hardLimitCapID, provider: .openai, name: "Organization hard limit",
            summary: "A monthly spend limit for the organization with Enforce a hard limit on. Past it, API "
                + "requests are refused.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://platform.openai.com/settings/organization/limits"),
            docURL: url("https://developers.openai.com/api/docs/guides/spend-limits"),
            steps: ["Open Settings › Organization › Limits.",
                    "Set a monthly spend limit and check Enforce a hard limit.",
                    "Save."],
            caveat: "OpenAI says enforcement isn't instantaneous, so spend can slightly exceed the limit."
        ),
        CapControl(
            id: "openai.project-limit", provider: .openai, name: "Project spend limits",
            summary: "A hard monthly limit on each project, so one app's keys can't spend the organization's "
                + "whole budget.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://platform.openai.com/settings/organization/limits"),
            docURL: url("https://developers.openai.com/api/docs/guides/spend-limits"),
            steps: ["In platform settings, switch to the project.",
                    "Open the project's Limits › Spend and set a hard limit.",
                    "Repeat for each project with live keys."],
            caveat: "Kill Cord checks only the organization limit over the API. Project limits are your mark."
        ),
        CapControl(
            id: "openai.spend-alert", provider: .openai, name: "Spend alerts",
            summary: "Email when monthly spend crosses an amount you choose. Traffic continues.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://platform.openai.com/settings/organization/limits"),
            docURL: url("https://developers.openai.com/api/docs/guides/spend-limits"),
            steps: ["On Settings › Organization › Limits, add an alert below your hard limit."],
            caveat: nil
        ),
        // Vercel. https://vercel.com/docs/spend-management
        CapControl(
            id: "vercel.pause-production", provider: .vercel, name: "Spend Management: pause production",
            summary: "A team or project budget that pauses production deployments when it's reached. Visitors "
                + "see a 503 until you resume.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fsettings%2Fbilling&title=Go+to+Billing"),
            docURL: url("https://vercel.com/docs/spend-management"),
            steps: ["Open team Settings › Billing and choose Spend Management.",
                    "Set a budget for the team or a project.",
                    "Turn on pausing production deployments when the budget is reached."],
            caveat: "Pro and Enterprise Flex only. Spend is checked every few minutes. It doesn't stop AI Gateway, "
                + "v0, or storage charges, and paused projects must be resumed by hand."
        ),
        CapControl(
            id: "vercel.budget-notifications", provider: .vercel, name: "Spend Management notifications",
            summary: "Web and email notifications at 50%, 75%, and 100% of a budget, and SMS at 100%.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fsettings%2Fbilling&title=Go+to+Billing"),
            docURL: url("https://vercel.com/docs/spend-management"),
            steps: ["Set a budget in Spend Management. Notifications come with it; check who receives them."],
            caveat: "Vercel has no API to read Spend Management settings, so Kill Cord trusts your mark."
        ),
        // Cloudflare. https://developers.cloudflare.com/billing/manage/spend-management/
        CapControl(
            id: CloudflareProvider.spendLimitCapID, provider: .cloudflare, name: "Spend Management limit",
            summary: "A spend limit for Workers or Durable Objects that blocks those operations until the next "
                + "billing period or until you change it.",
            enforcement: .hardStop, verification: .api,
            consoleURL: url("https://dash.cloudflare.com/?to=/:account/billing"),
            docURL: url("https://developers.cloudflare.com/billing/manage/spend-management/"),
            steps: ["Open Billing › Spend Management.",
                    "Add a limit for Workers (and Durable Objects, if you use them) that blocks usage.",
                    "Add the email alert too; dashboard limits have none by default."],
            caveat: "Cloudflare: metering delays and work in progress can let spend pass the limit. It covers "
                + "Workers and Durable Objects only."
        ),
        CapControl(
            id: "cloudflare.budget-alert", provider: .cloudflare, name: "Budget alerts",
            summary: "Email when projected spend for the billing period crosses an amount. Pay-as-you-go only.",
            enforcement: .alertOnly, verification: .selfReported,
            consoleURL: url("https://dash.cloudflare.com/?to=/:account/billing"),
            docURL: url("https://developers.cloudflare.com/billing/manage/budget-alerts/"),
            steps: ["Open Billing › Billable Usage and create a budget alert."],
            caveat: "Informational only. It's recalculated daily."
        ),
        // Twilio. https://www.twilio.com/docs/usage/api/usage-trigger
        CapControl(
            id: TwilioProvider.triggerCapID, provider: .twilio, name: "Usage trigger on total spend",
            summary: "A trigger on the Total Price category that calls a webhook when daily or monthly spend "
                + "crosses an amount.",
            enforcement: .alertOnly, verification: .api,
            consoleURL: url("https://console.twilio.com/"),
            docURL: url("https://www.twilio.com/docs/usage/api/usage-trigger"),
            steps: ["In the Console, open Billing and Usage › Usage and Spend › Usage Triggers.",
                    "Create a trigger on Total Price, triggered by price, recurring daily or monthly.",
                    "Point it at a webhook that alerts you (or suspends the account)."],
            caveat: "Twilio has no native hard spend cap. Triggers notify; they stop nothing on their own."
        ),
        // Neon. https://neon.com/docs/introduction/spending-limit
        CapControl(
            id: NeonProvider.thresholdCapID, provider: .neon, name: "Spending threshold",
            summary: "A monthly amount for the organization. Admins get email at 80% and 100%.",
            enforcement: .alertOnly, verification: .api,
            consoleURL: url("https://console.neon.tech/app/billing"),
            docURL: url("https://neon.com/docs/introduction/spending-limit"),
            steps: ["Pick the organization, open Billing, and find the Spending limit card.",
                    "Enable it and enter a monthly amount."],
            caveat: "Neon says it only sends alerts; projects keep running."
        ),
        CapControl(
            id: "neon.project-quotas", provider: .neon, name: "Project consumption quotas",
            summary: "Per-project limits on compute time, written data, and transfer. Past them, the project's "
                + "computes are suspended until the next billing period.",
            enforcement: .hardStop, verification: .selfReported,
            consoleURL: url("https://console.neon.tech/app/billing"),
            docURL: url("https://neon.com/docs/guides/consumption-limits"),
            steps: ["Set quotas on each project with the Neon API (PATCH /projects/{id}, settings.quota).",
                    "Also cap autoscaling: set each compute's maximum size in the project's settings."],
            caveat: "Quotas are in usage units, not dollars, and each update replaces the whole quota object."
        ),
        // Supabase. https://supabase.com/docs/guides/platform/cost-control
        CapControl(
            id: "supabase.spend-cap", provider: .supabase, name: "Spend Cap",
            summary: "On the Pro plan, stops usage-based charges for covered items (egress, storage, MAU, and "
                + "more) once you pass the plan's quota.",
            enforcement: .partialStop, verification: .selfReported,
            consoleURL: url("https://supabase.com/dashboard/org/_/billing"),
            docURL: url("https://supabase.com/docs/guides/platform/cost-control"),
            steps: ["Open the organization's Billing page and find Cost Control.",
                    "Make sure the Spend Cap is on."],
            caveat: "Compute, custom domains, IPv4, PITR, and some other items bill even with the cap on. "
                + "Supabase has no API for it, so Kill Cord trusts your mark."
        ),
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
        )
    ]

    public static func controls(for provider: ProviderID) -> [CapControl] {
        controls.filter { $0.provider == provider }
    }

    public static func control(_ id: String) -> CapControl? {
        controls.first { $0.id == id }
    }
}

/// What the person has done in the audit, per cap. Saved in UserDefaults: it holds no secrets.
public struct CapAuditState: Sendable, Equatable, Codable {
    public enum Mark: Sendable, Equatable, Codable {
        /// The person says it's set.
        case done(at: Date)
        /// The person says it doesn't apply (they don't use that service).
        case notApplicable(at: Date)
    }

    public private(set) var marks: [String: Mark]
    /// The latest API readings, for caps that can be checked.
    public private(set) var verifications: [String: CapVerification]

    /// Caps can be removed in the console, so a self-reported "done" asks to be checked again after this long.
    public static let recheckAfter: TimeInterval = 30 * 24 * 3600

    public init(marks: [String: Mark] = [:], verifications: [String: CapVerification] = [:]) {
        self.marks = marks
        self.verifications = verifications
    }

    public mutating func mark(_ capID: String, _ mark: Mark?) {
        marks[capID] = mark
    }

    public mutating func record(_ results: [CapVerification]) {
        for result in results { verifications[result.capID] = result }
    }

    public enum Status: Equatable, Sendable {
        case notDone
        /// Marked done by the person; `recheck` is true once it's old enough to look again.
        case markedDone(at: Date, recheck: Bool)
        case notApplicable
        /// The provider's API says it's on.
        case verifiedOn(String, at: Date)
        /// The provider's API says it's off, whatever the person marked.
        case verifiedOff(String, at: Date)
        /// The cap was hit and is stopping usage right now.
        case enforced(String, at: Date)

        public var isDone: Bool {
            switch self {
            case .markedDone, .notApplicable, .verifiedOn, .enforced: true
            case .notDone, .verifiedOff: false
            }
        }

        public var needsAttention: Bool {
            switch self {
            case .notDone, .verifiedOff: true
            case .markedDone(_, let recheck): recheck
            case .notApplicable, .verifiedOn, .enforced: false
            }
        }
    }

    /// An API reading wins over a mark, since it's what the provider says now. A stale reading (from before
    /// the person's latest mark) doesn't override that mark.
    public func status(of control: CapControl, now: Date) -> Status { // swiftlint:disable:this cyclomatic_complexity
        let mark = marks[control.id]
        if control.verification == .api, let reading = verifications[control.id] {
            let markDate: Date? = switch mark {
            case .done(let at), .notApplicable(let at): at
            case nil: nil
            }
            if markDate.map({ reading.checkedAt >= $0 }) ?? true {
                switch reading.status {
                case .on(let detail): return .verifiedOn(detail, at: reading.checkedAt)
                case .off(let detail):
                    if case .notApplicable = mark { return .notApplicable }
                    return .verifiedOff(detail, at: reading.checkedAt)
                case .enforced(let detail): return .enforced(detail, at: reading.checkedAt)
                }
            }
        }
        switch mark {
        case .done(let at): return .markedDone(at: at, recheck: now.timeIntervalSince(at) >= Self.recheckAfter)
        case .notApplicable: return .notApplicable
        case nil: return .notDone
        }
    }

    public struct Progress: Equatable, Sendable {
        public let done: Int
        public let total: Int
        public let needsAttention: Int

        public var isComplete: Bool { done == total && needsAttention == 0 }
    }

    public func progress(for provider: ProviderID, now: Date) -> Progress {
        let statuses = CapsCatalog.controls(for: provider).map { status(of: $0, now: now) }
        return Progress(done: statuses.filter(\.isDone).count, total: statuses.count,
                        needsAttention: statuses.filter(\.needsAttention).count)
    }

    /// Caps marked done long enough ago that they're worth checking again.
    public func dueForRecheck(now: Date) -> [CapControl] {
        CapsCatalog.controls.filter {
            if case .markedDone(_, true) = status(of: $0, now: now) { return true }
            return false
        }
    }
}
