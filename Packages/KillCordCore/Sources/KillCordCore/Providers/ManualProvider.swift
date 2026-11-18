// A plan the person typed in. No network: "reading" it only checks the fields and rolls the renewal date
// forward to the next one, so reminders stay right month after month.
import Foundation

public struct ManualProvider: SpendProvider {
    public let id = ProviderID.manual

    public init() {}

    public func validate(_ credentials: ProviderCredentials, now: Date) async throws {
        _ = try ManualPlan(credentials, now: now)
    }

    public func fetchSpend(_ credentials: ProviderCredentials, now: Date) async throws -> SpendSnapshot {
        SpendSnapshot(provider: id, today: nil, month: nil, manual: try ManualPlan(credentials, now: now), fetchedAt: now)
    }
}

extension ProviderInfo {
    static let manual = ProviderInfo(
        id: .manual, name: "Manual entry", capability: .enteredByHand,
        fields: [
            CredentialField(id: "serviceName", label: "Service name", placeholder: "Truelist", isSecret: false,
                            help: "What Kill Cord calls it."),
            CredentialField(id: "plan", label: "Plan", placeholder: "Starter", isSecret: false, isOptional: true),
            CredentialField(id: "price", label: "Price in USD", placeholder: "49", isSecret: false, isOptional: true),
            CredentialField(id: "period", label: "Billed", isSecret: false,
                            choices: ManualPlan.Period.allCases.map(\.rawValue)),
            CredentialField(id: "renewsOn", label: "Next renewal", placeholder: "2026-12-03", isSecret: false,
                            help: "As year-month-day. Kill Cord moves it forward each period."),
            CredentialField(id: "allowance", label: "Credits included", placeholder: "10000", isSecret: false,
                            isOptional: true, help: "What the plan includes each period, if it counts something."),
            CredentialField(id: "allowanceUnit", label: "Called", placeholder: "credits", isSecret: false,
                            isOptional: true),
            CredentialField(id: "remindDays", label: "Remind me days before", isSecret: false,
                            choices: ManualPlan.remindChoices)
        ],
        keyKind: "nothing secret", keyURL: nil, keyPowerWarning: nil,
        lag: ProviderLag(typical: 0, note: "Entered by you. Kill Cord never contacts the service, so it can't "
            + "tell if the plan changed."),
        billingTimeZone: utc, minimumRefreshInterval: 60 * 60,
        consoleURL: url("https://killcord.app/")
    )
}
