// Usage broken down by unit, for providers that report quantities instead of dollars (Neon). Kill Cord Teams,
// unit 9.
//
// There is deliberately no Money anywhere in this file. A provider that reports usage units must never be shown
// as dollars, so the type can't carry an amount of money: a quantity is a Decimal with the provider's own metric
// name and raw unit beside it. Converting to dollars would need the provider's price list, which is an estimate
// and is out of scope (teams-spec.md, v1 out: "A number is the provider's or it is absent").
import Foundation

/// One provider-reported quantity for a unit (or for nobody) in a time bucket.
public struct AttributedQuantity: Codable, Hashable, Sendable {
    public var bucketStart: Date
    public var bucketEnd: Date
    /// Nil when the provider reports the quantity for no unit of this kind.
    public var unit: AttributionUnitRef?
    /// The provider's metric name, for example Neon's `compute_unit_seconds`.
    public var metric: String
    /// In the metric's raw unit (see `UsageBreakdown.rawUnits`).
    public var quantity: Decimal

    public init(bucketStart: Date, bucketEnd: Date, unit: AttributionUnitRef?, metric: String, quantity: Decimal) {
        self.bucketStart = bucketStart
        self.bucketEnd = bucketEnd
        self.unit = unit
        self.metric = metric
        self.quantity = quantity
    }
}

/// A provider's usage for a range, split by unit. Units, never money.
public struct UsageBreakdown: Codable, Sendable {
    public var provider: ProviderID
    public var dimension: AttributionDimension
    public var rangeStart: Date
    public var rangeEnd: Date
    public var rows: [AttributedQuantity]
    /// Raw unit per metric, as the provider documents it ("CU-seconds", "bytes").
    public var rawUnits: [String: String]
    public var units: [AttributionUnit]

    public init(provider: ProviderID, dimension: AttributionDimension, rangeStart: Date, rangeEnd: Date,
                rows: [AttributedQuantity], rawUnits: [String: String], units: [AttributionUnit] = []) {
        self.provider = provider
        self.dimension = dimension
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.rows = rows
        self.rawUnits = rawUnits
        self.units = units
    }

    /// The total per metric across every unit.
    public var totals: [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for row in rows { totals[row.metric, default: 0] += row.quantity }
        return totals
    }

    /// Per unit (nil: unassigned), per metric.
    public var byUnit: [AttributionUnitRef?: [String: Decimal]] {
        var result: [AttributionUnitRef?: [String: Decimal]] = [:]
        for row in rows { result[row.unit, default: [:]][row.metric, default: 0] += row.quantity }
        return result
    }
}
