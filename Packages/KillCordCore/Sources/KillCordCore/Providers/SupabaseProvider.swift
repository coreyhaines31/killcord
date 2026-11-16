// Supabase has no billing, spend, or usage-cost API.
// Management API reference: https://supabase.com/docs/reference/api (checked: the only billing path is
// /v1/projects/{ref}/billing/addons, which lists add-ons, not spend)
// Spend Cap: https://supabase.com/docs/guides/platform/cost-control
//
// So there's nothing to connect and nothing to fetch. The caps audit still covers the Spend Cap, and the
// person checks the Upcoming Invoice on the Billing page.
import Foundation

public struct SupabaseProvider: SpendProvider {
    public let id = ProviderID.supabase

    public init() {}

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        throw SpendError.noUsageAPI
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        throw SpendError.noUsageAPI
    }
}
