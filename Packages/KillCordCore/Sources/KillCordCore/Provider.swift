import Foundation

/// The usage-billed providers Kill Cord knows. Order is the order they're listed in: the two most likely to
/// surprise a bill first, then the rest, then services Kill Cord reads a balance from.
public enum ProviderID: String, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case anthropic
    case google
    case openai
    case vercel
    case cloudflare
    case twilio
    case neon
    case supabase
    // Prepaid balances and plan allowances.
    case openrouter
    case dataforseo
    case ahrefs
    case firecrawl
    case treg
    case monid
    case fal
    case elevenlabs
    case xai
    case deepseek
    case apify
    case tavily
    case deepgram
    case runway
    case serpapi
    case brightdata
    case scrapecreators
    case stability
    case moonshot
    case exa
    case scrapingbee
    case scrapfly
    case kie
    case bland
    case llamacloud
    case runpod
    case deepinfra
    case xapi
    case bfl
    case digitalocean
    case telnyx
    case luma
    case heygen
    case browseruse
    case novita
    case baseten
    case hunter
    case zerobounce
    /// A service the person sets up: an https address and where the balance is in its JSON.
    case custom
    /// A paid service with no API: a plan, price and renewal date the person types in.
    case manual

    public var id: String { rawValue }

    public static func < (lhs: ProviderID, rhs: ProviderID) -> Bool {
        let order = Self.allCases
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }

    public var info: ProviderInfo { ProviderInfo.all[self]! }
}

/// What a provider's API can tell Kill Cord about spend. Shown plainly in the UI, so nobody mistakes a
/// missing number for $0.
public enum SpendCapability: Hashable, Sendable {
    /// The API returns spend in money.
    case dollars
    /// The API returns this month's spend in money, but nothing finer than a month (DeepInfra).
    case monthDollars
    /// The API returns usage (compute hours, bytes) but not money.
    case usageUnitsOnly
    /// There is no API for spend or usage. The caps audit still works.
    case noUsageAPI
    /// Spend is available only after one-time setup outside Kill Cord (Google's BigQuery billing export).
    case requiresSetup(String)
    /// The API reports what's left of a prepaid balance or plan allowance, plus spend for `spend`'s periods.
    case balance(spend: SpendPeriods)
    /// No API: the person types in the plan, and Kill Cord reminds before it renews.
    case enteredByHand

    public var summary: String {
        switch self {
        case .dollars: "Shows spend in dollars."
        case .monthDollars: "Shows this month's spend in dollars. The API doesn't report a day."
        case .usageUnitsOnly: "Shows usage, not dollars: the API doesn't report money."
        case .noUsageAPI: "No spend API. Kill Cord can't show spend here, but the caps audit still works."
        case .requiresSetup(let what): "Shows spend after one-time setup: \(what)."
        case .balance(let spend) where spend.isEmpty: "Shows the balance left, not spend."
        case .balance: "Shows the balance left, and spend where the API reports it."
        case .enteredByHand: "Shows the plan you entered and reminds before it renews. Not live."
        }
    }

    /// Whether today's spend is reported, so a missing number is worth saying.
    public var countsToday: Bool {
        switch self {
        case .dollars, .requiresSetup: true
        case .monthDollars, .usageUnitsOnly, .noUsageAPI, .enteredByHand: false
        case .balance(let spend): spend.contains(.today)
        }
    }

    /// Whether this month's spend is reported.
    public var countsMonth: Bool {
        switch self {
        case .dollars, .monthDollars, .requiresSetup: true
        case .usageUnitsOnly, .noUsageAPI, .enteredByHand: false
        case .balance(let spend): spend.contains(.month)
        }
    }

    /// Whether any spend in money is reported.
    public var showsMoney: Bool { countsToday || countsMonth }

    /// Whether a balance is the headline.
    public var showsBalance: Bool {
        if case .balance = self { return true }
        return false
    }
}

/// Which spend periods a balance provider also reports.
public struct SpendPeriods: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let today = SpendPeriods(rawValue: 1)
    public static let month = SpendPeriods(rawValue: 2)
}

/// One thing a person pastes in to connect a provider.
public struct CredentialField: Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let placeholder: String
    /// Secret fields are drawn as secure text and never shown again after saving. Every field, secret or
    /// not, is saved only in the Keychain.
    public let isSecret: Bool
    public let isOptional: Bool
    /// Multi-line input, for a pasted JSON key file.
    public let isMultiline: Bool
    public let help: String
    /// A fixed set of values, drawn as a picker. The first is the default when nothing is saved.
    public let choices: [String]
    /// Rarely needed: drawn under a collapsed "Advanced" disclosure.
    public let isAdvanced: Bool

    public init(id: String, label: String, placeholder: String = "", isSecret: Bool, isOptional: Bool = false,
                isMultiline: Bool = false, help: String = "", choices: [String] = [], isAdvanced: Bool = false) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.isSecret = isSecret
        self.isOptional = isOptional || !choices.isEmpty
        self.isMultiline = isMultiline
        self.help = help
        self.choices = choices
        self.isAdvanced = isAdvanced
    }
}

/// Everything static about a provider: names, what its API offers, what it needs, and how far behind it runs.
public struct ProviderInfo: Sendable {
    public let id: ProviderID
    public let name: String
    public let capability: SpendCapability
    /// Fields to connect. Empty for providers with nothing to connect (Supabase).
    public let fields: [CredentialField]
    /// The kind of key, in a few words: "Admin API key".
    public let keyKind: String
    /// Where to create that key.
    public let keyURL: URL?
    /// An honest note about how much power that key has, shown before saving it.
    public let keyPowerWarning: String?
    /// How far behind the provider's own numbers usually run.
    public let lag: ProviderLag
    /// The clock the provider's "day" and "month" follow.
    public let billingTimeZone: TimeZone
    /// Asking more often than this gains nothing, or risks a rate limit.
    public let minimumRefreshInterval: TimeInterval
    /// Where the provider's own spend page is, to compare against.
    public let consoleURL: URL

    public var connects: Bool { !fields.isEmpty }
}

/// How far behind real time a provider's spend data runs, as documented by the provider.
public struct ProviderLag: Hashable, Sendable {
    public let typical: TimeInterval
    public let note: String

    public init(typical: TimeInterval, note: String) {
        self.typical = typical
        self.note = note
    }
}

extension ProviderInfo {
    static let utc = TimeZone(identifier: "UTC")!
    // Google's billing day and invoice month follow US Pacific time.
    static let pacific = TimeZone(identifier: "America/Los_Angeles")!

    static func url(_ string: String) -> URL { URL(string: string)! }

    public static let all: [ProviderID: ProviderInfo] = Dictionary(uniqueKeysWithValues: ([
        ProviderInfo(
            id: .anthropic, name: "Anthropic", capability: .dollars,
            fields: [CredentialField(id: "apiKey", label: "API key", placeholder: "sk-ant-…", isSecret: true,
                                     help: "A service account key or personal key that isn't scoped to a "
                                        + "workspace, or an Admin API key.")],
            keyKind: "Admin API key, or a service account or personal key that isn't scoped to a workspace",
            keyURL: url("https://platform.claude.com/settings/keys"),
            keyPowerWarning: "Anthropic has no read-only key for the cost report. A service account or personal "
                + "key has the same permissions as the account it's linked to, so it can do whatever that "
                + "account's role allows. An Admin API key can also manage members, workspaces, and API keys. "
                + "Kill Cord only reads the cost report, and the key stays in your Mac's Keychain, but treat it "
                + "like a password and revoke it in the Console if it leaks.",
            lag: ProviderLag(typical: 5 * 60, note: "Anthropic's cost report usually catches up within 5 minutes. "
                + "Priority Tier costs aren't included."),
            billingTimeZone: utc, minimumRefreshInterval: 5 * 60,
            consoleURL: url("https://platform.claude.com/cost")
        ),
        ProviderInfo(
            id: .google, name: "Google Cloud and Gemini",
            capability: .requiresSetup("Cloud Billing export to BigQuery, and a read-only service account"),
            fields: [
                CredentialField(id: "serviceAccountJSON", label: "Service account key (JSON)",
                                placeholder: "{ \"type\": \"service_account\", … }", isSecret: true,
                                isMultiline: true,
                                help: "Paste the whole JSON key file, braces included."),
                CredentialField(id: "exportTable", label: "Billing export table",
                                placeholder: "my-project.billing.gcp_billing_export_v1_XXXXXX_XXXXXX_XXXXXX",
                                isSecret: false,
                                help: "The standard usage cost table, as project.dataset.table."),
                CredentialField(id: "billingAccountID", label: "Billing account ID", placeholder: "0123AB-4567CD-89EF01",
                                isSecret: false, isOptional: true,
                                help: "Optional. Lets Kill Cord check your budgets and spend caps. Needs Billing "
                                    + "Account Viewer for the service account.")
            ],
            keyKind: "Service account key with read access to the billing export",
            keyURL: url("https://console.cloud.google.com/iam-admin/serviceaccounts"),
            keyPowerWarning: "Google recommends avoiding service account keys where you can, and your organization "
                + "may block creating them. Give this account only BigQuery Data Viewer on the export dataset, "
                + "BigQuery Job User, and optionally Billing Account Viewer. Nothing that can change resources.",
            lag: ProviderLag(typical: 24 * 3600, note: "Google's billing export runs hours behind, typically up to "
                + "a day, with no guarantee. Today's number usually reads low."),
            billingTimeZone: pacific, minimumRefreshInterval: 60 * 60,
            consoleURL: url("https://console.cloud.google.com/billing/reports")
        ),
        ProviderInfo(
            id: .openai, name: "OpenAI", capability: .dollars,
            fields: [CredentialField(id: "apiKey", label: "Admin API key", placeholder: "sk-admin-…", isSecret: true)],
            keyKind: "Admin API key",
            keyURL: url("https://platform.openai.com/settings/organization/admin-keys"),
            keyPowerWarning: "OpenAI admin keys work across your whole organization. If the read-only option is "
                + "offered when you create it, choose it: Kill Cord only reads costs and spend limits. The key "
                + "stays in your Mac's Keychain.",
            lag: ProviderLag(typical: 60 * 60, note: "OpenAI doesn't document how far behind costs run. Expect "
                + "today's number to trail what you've used."),
            billingTimeZone: utc, minimumRefreshInterval: 5 * 60,
            consoleURL: url("https://platform.openai.com/settings/organization/usage")
        ),
        ProviderInfo(
            id: .vercel, name: "Vercel", capability: .dollars,
            fields: [
                CredentialField(id: "token", label: "Access token", placeholder: "Vercel token", isSecret: true),
                CredentialField(id: "teamID", label: "Team ID", placeholder: "team_…", isSecret: false,
                                isOptional: true,
                                help: "Optional. Find it under Team Settings › General.")
            ],
            keyKind: "Access token",
            keyURL: url("https://vercel.com/account/tokens"),
            keyPowerWarning: "Vercel tokens have the same access as your account on the teams they're scoped to. "
                + "Scope it to one team and give it an expiry. Kill Cord only reads billing charges.",
            lag: ProviderLag(typical: 24 * 3600, note: "Vercel reports charges by day and doesn't document how "
                + "far behind they run. Today may be missing until tomorrow."),
            billingTimeZone: utc, minimumRefreshInterval: 30 * 60,
            consoleURL: url("https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fsettings%2Fbilling&title=Go+to+Billing")
        ),
        ProviderInfo(
            id: .cloudflare, name: "Cloudflare", capability: .dollars,
            fields: [
                CredentialField(id: "token", label: "API token", placeholder: "Cloudflare API token", isSecret: true),
                CredentialField(id: "accountID", label: "Account ID", placeholder: "32-character account ID",
                                isSecret: false, help: "On the account's home page in the dashboard.")
            ],
            keyKind: "API token with Billing Read",
            keyURL: url("https://dash.cloudflare.com/profile/api-tokens"),
            keyPowerWarning: nil,
            lag: ProviderLag(typical: 24 * 3600, note: "Cloudflare updates billable usage once a day, so today "
                + "usually isn't reported yet. Pay-as-you-go accounts only; the month is your billing period."),
            billingTimeZone: utc, minimumRefreshInterval: 60 * 60,
            consoleURL: url("https://dash.cloudflare.com/?to=/:account/billing")
        ),
        ProviderInfo(
            id: .twilio, name: "Twilio", capability: .dollars,
            fields: [
                CredentialField(id: "accountSID", label: "Account SID", placeholder: "AC…", isSecret: false,
                                help: "On the Twilio Console home page."),
                CredentialField(id: "apiKeySID", label: "API key SID", placeholder: "SK…", isSecret: false,
                                isOptional: true,
                                help: "Leave empty to use your Auth Token as the secret below."),
                CredentialField(id: "secret", label: "API key secret or Auth Token", placeholder: "Secret",
                                isSecret: true)
            ],
            keyKind: "API key (or Auth Token)",
            keyURL: url("https://console.twilio.com/"),
            keyPowerWarning: "Twilio has no read-only key. A Standard API key can send messages and make calls on "
                + "your account, and an Auth Token can do even more. Use a Standard API key you can revoke.",
            lag: ProviderLag(typical: 15 * 60, note: "Twilio usage records trail real usage by a little; each "
                + "reading says how current it is."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.twilio.com/")
        ),
        ProviderInfo(
            id: .neon, name: "Neon", capability: .usageUnitsOnly,
            fields: [
                CredentialField(id: "apiKey", label: "API key", placeholder: "Neon API key", isSecret: true),
                CredentialField(id: "orgID", label: "Organization ID", placeholder: "org-…", isSecret: false)
            ],
            keyKind: "Organization API key",
            keyURL: url("https://console.neon.tech/"),
            keyPowerWarning: "Neon has no read-only API key. An organization key can manage every project in the "
                + "organization. Kill Cord only reads consumption and your spending threshold.",
            lag: ProviderLag(typical: 15 * 60, note: "Neon updates consumption about every 15 minutes. It reports "
                + "usage, not dollars. Launch, Scale, and Agent plans only."),
            billingTimeZone: utc, minimumRefreshInterval: 15 * 60,
            consoleURL: url("https://console.neon.tech/app/billing")
        ),
        ProviderInfo(
            id: .supabase, name: "Supabase", capability: .noUsageAPI, fields: [],
            keyKind: "Nothing to connect", keyURL: nil, keyPowerWarning: nil,
            lag: ProviderLag(typical: 0, note: "Supabase has no billing or usage API, so Kill Cord can't show "
                + "spend. Check the Upcoming Invoice on the Billing page."),
            billingTimeZone: utc, minimumRefreshInterval: 24 * 3600,
            consoleURL: url("https://supabase.com/dashboard/org/_/billing")
        )
    ] + balanceProviders + moreBalanceProviders + batch3Providers + [custom, manual]).map { ($0.id, $0) })
}
