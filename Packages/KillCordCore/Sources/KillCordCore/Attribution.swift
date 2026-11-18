// Attribution: who and what spend belongs to, for Kill Cord Teams (docs/product/teams-spec.md, sections 2 and 3).
//
// A provider breaks its spend down by "units": an API key, a workspace, a project, a user, a service account
// or a federated identity. Adapters return the provider's own breakdown as `AttributedSpend` rows and the
// provider's own total for the same range, so a report always reconciles: assigned rows plus unassigned rows
// equal the provider's total, to the cent, or the report says it doesn't. Nothing here is estimated. Every
// amount is the provider's, in `Decimal`.
//
// The cloud worker writes these to Postgres and the web app reads them, so every type is Codable with stable
// raw values. Keys never appear here: a key is described only by its last four characters ("Ending in igAA").
import Foundation

/// What a provider breaks spend down by.
public enum AttributionUnitKind: String, Codable, Sendable, CaseIterable {
    case apiKey = "api_key"
    case workspace
    case project
    case user
    case serviceAccount = "service_account"
    /// A cloud identity (AWS, Google Cloud, Azure, OIDC) that Anthropic attributes usage to.
    case federated
}

/// Identifies a unit within one provider account.
public struct AttributionUnitRef: Codable, Hashable, Sendable, Comparable {
    public var kind: AttributionUnitKind
    /// The provider's id for it (`apikey_…`, `wrkspc_…`, `user_…`, `proj_…`).
    public var externalID: String

    public init(kind: AttributionUnitKind, externalID: String) {
        self.kind = kind
        self.externalID = externalID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.kind.rawValue, lhs.externalID) < (rhs.kind.rawValue, rhs.externalID)
    }
}

/// A unit as the provider describes it, from its admin lists or from the actor on a cost row.
public struct AttributionUnit: Codable, Hashable, Sendable {
    public var provider: ProviderID
    public var kind: AttributionUnitKind
    public var externalID: String
    /// The provider's name for it: a key's name, a workspace or project name, a person's name.
    public var label: String?
    /// "Ending in igAA" for keys. Never more than the last four characters of the provider's own redacted hint.
    public var keyHint: String?
    /// The person's email, when the provider reports one (a user, or the user who owns a key).
    public var ownerEmail: String?
    /// The workspace (Anthropic) or project (OpenAI) a key belongs to.
    public var parentID: String?
    /// The provider's status for it ("active", "archived", "expired", …), as sent.
    public var status: String?
    public var expiresAt: Date?

    public init(provider: ProviderID, kind: AttributionUnitKind, externalID: String, label: String? = nil,
                keyHint: String? = nil, ownerEmail: String? = nil, parentID: String? = nil, status: String? = nil,
                expiresAt: Date? = nil) {
        self.provider = provider
        self.kind = kind
        self.externalID = externalID
        self.label = label
        self.keyHint = keyHint
        self.ownerEmail = ownerEmail
        self.parentID = parentID
        self.status = status
        self.expiresAt = expiresAt
    }

    public var ref: AttributionUnitRef { AttributionUnitRef(kind: kind, externalID: externalID) }

    /// "Ending in igAA" from a provider's redacted key ("sk-ant-api03-R2D...igAA", "sk-abc****wxyz"). Only the
    /// last four letters or digits survive; nil when there aren't four.
    public static func keyHint(fromRedacted redacted: String?) -> String? {
        guard let redacted else { return nil }
        let tail = redacted.reversed().prefix { $0.isLetter || $0.isNumber }
        guard tail.count >= 4 else { return nil }
        return "Ending in \(String(tail.prefix(4).reversed()))"
    }
}

/// Spend that the provider reported, or (in the cloud) that an admin assigned. Adapters only produce `reported`.
public enum AttributionSource: String, Codable, Sendable {
    case reported
}

/// One row of a provider's breakdown: an amount in a time bucket, for a unit or for nobody (unassigned).
public struct AttributedSpend: Codable, Hashable, Sendable {
    public var bucketStart: Date
    public var bucketEnd: Date
    /// Nil when the provider attributes the amount to no unit of this kind: shown as "Unassigned".
    public var unit: AttributionUnitRef?
    /// Set only when the report was also grouped by model.
    public var model: String?
    public var amount: Money
    public var source: AttributionSource

    public init(bucketStart: Date, bucketEnd: Date, unit: AttributionUnitRef?, model: String? = nil,
                amount: Money, source: AttributionSource = .reported) {
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.unit = unit
        self.model = model
        self.amount = amount
        self.source = source
    }
}

/// Token and request counts for a unit in a time bucket. Never turned into money: a number is the provider's
/// cost report or it's absent.
public struct AttributedUsage: Codable, Hashable, Sendable {
    public var bucketStart: Date
    public var bucketEnd: Date
    public var unit: AttributionUnitRef?
    public var model: String?
    /// All input tokens, cached and uncached.
    public var inputTokens: Int
    public var cachedInputTokens: Int
    public var outputTokens: Int
    public var requests: Int?

    public init(bucketStart: Date, bucketEnd: Date, unit: AttributionUnitRef?, model: String? = nil,
                inputTokens: Int, cachedInputTokens: Int, outputTokens: Int, requests: Int?) {
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.unit = unit
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.requests = requests
    }
}

/// How a report is broken down.
public enum AttributionDimension: String, Codable, Sendable {
    /// Anthropic's `actor`: a user, else a service account, else a federated identity, else the key itself.
    case actor
    case apiKey = "api_key"
    case workspace
    case project
    /// OpenAI's `user_id`. What it identifies is not verified (see `AttributionReport.meaningVerified`).
    case user
}

/// A provider's breakdown for a range, with the provider's own total for the same range.
public struct AttributionReport: Codable, Sendable {
    public var provider: ProviderID
    public var dimension: AttributionDimension
    /// Inclusive start and exclusive end, as requested (UTC day boundaries).
    public var rangeStart: Date
    public var rangeEnd: Date
    public var rows: [AttributedSpend]
    /// The provider's total for the range, from the same query without grouping.
    public var providerTotal: MoneyTotals
    /// Anthropic's `data_refreshed_at` (the oldest seen while fetching): spend after it is missing or partial.
    /// Nil for providers that don't say, or when no data covers the range yet.
    public var dataRefreshedAt: Date?
    /// False when Kill Cord hasn't verified what the provider's grouping identifies. OpenAI's `user_id` is
    /// documented only as "the user ID of the grouped costs result"; until it's checked against a real
    /// organization it must not be shown as a person.
    public var meaningVerified: Bool
    /// Units the rows themselves describe (Anthropic's actor carries a person's name and email), merged with
    /// the admin lists by the caller.
    public var units: [AttributionUnit]

    public init(provider: ProviderID, dimension: AttributionDimension, rangeStart: Date, rangeEnd: Date,
                rows: [AttributedSpend], providerTotal: MoneyTotals, dataRefreshedAt: Date?, meaningVerified: Bool,
                units: [AttributionUnit] = []) {
        self.provider = provider
        self.dimension = dimension
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.rows = rows
        self.providerTotal = providerTotal
        self.dataRefreshedAt = dataRefreshedAt
        self.meaningVerified = meaningVerified
        self.units = units
    }

    public var assigned: MoneyTotals { MoneyTotals(rows.filter { $0.unit != nil }.map(\.amount)) }
    public var unassigned: MoneyTotals { MoneyTotals(rows.filter { $0.unit == nil }.map(\.amount)) }

    /// The provider's total minus assigned and unassigned, per currency. Empty when the report reconciles.
    public var gap: MoneyTotals {
        var gap = MoneyTotals()
        for money in providerTotal.amounts { gap.add(money) }
        for money in assigned.amounts + unassigned.amounts { gap.add(Money(-money.amount, money.currency)) }
        return MoneyTotals(gap.amounts.filter { $0.amount != 0 })
    }

    /// Assigned plus unassigned equals the provider's total exactly.
    public var reconciles: Bool { gap.isEmpty }

    /// Totals per unit (nil key: unassigned) across buckets and models.
    public var byUnit: [AttributionUnitRef?: MoneyTotals] {
        var totals: [AttributionUnitRef?: MoneyTotals] = [:]
        for row in rows { totals[row.unit, default: MoneyTotals()].add(row.amount) }
        return totals
    }
}

/// The range a report may cover was refused before any request.
public enum AttributionRangeError: Error, Equatable, Sendable {
    case empty
    /// The provider keeps history only back to this date.
    case beforeEarliest(Date)
}

/// Splits ranges into the windows a provider accepts.
public enum AttributionWindows {
    /// Consecutive [start, end) windows of at most `maxDays` days that exactly cover the range.
    public static func split(start: Date, end: Date, maxDays: Int) -> [DateInterval] {
        guard end > start, maxDays > 0 else { return [] }
        let step = TimeInterval(maxDays * 86_400)
        var windows: [DateInterval] = []
        var cursor = start
        while cursor < end {
            let next = min(cursor.addingTimeInterval(step), end)
            windows.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return windows
    }

    /// Midnight UTC on or before a date.
    public static func utcDayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.startOfDay(for: date)
    }
}
