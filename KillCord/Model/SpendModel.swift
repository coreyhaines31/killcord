import Foundation
import KillCordCore
import Network
import Observation

/// Owns the connections: reads each one's key from the Keychain when it needs it, asks each provider on the
/// scheduler's timetable while the Mac is awake, and keeps the latest spend. A provider can have several
/// connections (two Anthropic organizations); each has its own key, name, readings and failures.
@MainActor
@Observable
final class SpendModel {
    private(set) var registry = ConnectionRegistry()
    private(set) var states: [UUID: ProviderState] = [:]
    private(set) var audit: CapAuditState
    private(set) var isRefreshing = false
    private(set) var isOnline = true
    private(set) var isAsleep = false
    private(set) var lastWake: Date?
    let launchedAt = Date()
    /// Sample data, for screenshots. Never touches the Keychain or the network.
    let isDemo: Bool

    /// After each refresh that changed something.
    var onChange: (() -> Void)?
    /// After each successful reading, for threshold notifications.
    var onSpend: (([ProviderState]) -> Void)?

    private let secrets: SecretStore
    private var credentials: CredentialStore
    private let providers: [ProviderID: SpendProvider]
    @ObservationIgnored private var scheduler: RefreshScheduler
    @ObservationIgnored private var timer: Timer?
    /// Connections being asked right now.
    private(set) var inFlight: Set<UUID> = []
    @ObservationIgnored private var lastCapCheck: [UUID: Date] = [:]
    private let pathMonitor = NWPathMonitor()

    /// Cap settings change rarely; ask at most this often (plus on connect and on request).
    static let capCheckInterval: TimeInterval = 6 * 3600

    init(secrets: SecretStore = KeychainSecretStore(), http: HTTPClient = URLSessionHTTPClient(), isDemo: Bool = false) {
        self.secrets = secrets
        credentials = CredentialStore(secrets: secrets)
        providers = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, SpendProviders.make($0, http: http)) })
        scheduler = RefreshScheduler(interval: Preferences.refreshInterval)
        self.isDemo = isDemo
        audit = isDemo ? DemoData.audit() : Preferences.capAudit
    }

    func start() {
        if isDemo {
            showSample(registry: DemoData.registry(), states: DemoData.states())
            return
        }
        let fallback = Preferences.migrate(secrets: secrets)
        credentials = CredentialStore(secrets: secrets, legacyFallback: fallback)
        var registry = Preferences.connections
        if registry.reconcile(hasItem: credentials.hasItem) { Preferences.connections = registry }
        self.registry = registry
        for state in SpendCache.load() where registry.record(state.connectionID) != nil {
            states[state.connectionID] = state
        }
        for record in registry.records {
            if states[record.id] == nil {
                states[record.id] = ProviderState(provider: record.provider, connectionID: record.id)
            }
            states[record.id]?.refreshFloor = customConfig(record.id)?.interval
            scheduler.add(record.id, provider: record.provider, now: Date(), floor: states[record.id]?.refreshFloor)
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.setOnline(online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.killcord.KillCord.path"))
        tick()
    }

    // MARK: - What the panel shows

    var connections: [ConnectionRecord] { registry.records }

    /// Providers with at least one connection.
    var connected: [ProviderID] { registry.providers }

    func connection(_ id: UUID) -> ConnectionRecord? { registry.record(id) }

    func connections(for provider: ProviderID) -> [ConnectionRecord] { registry.records(for: provider) }

    var freshnessContext: FreshnessContext {
        FreshnessContext(now: Date(), launchedAt: isDemo ? Date.distantPast : launchedAt, lastWake: lastWake,
                         isAsleep: isAsleep, isOnline: isOnline, interval: scheduler.interval)
    }

    /// Every connection's state, in registry order.
    var orderedStates: [ProviderState] { registry.records.compactMap { states[$0.id] } }

    func summary(now: Date = Date()) -> SpendSummary {
        var context = freshnessContext
        context.now = now
        return SpendSummary(states: orderedStates, names: registry.names, context: context)
    }

    func freshness(_ id: UUID, now: Date = Date()) -> Freshness {
        guard let state = states[id] else { return .neverChecked }
        var context = freshnessContext
        context.now = now
        return Freshness.of(state, context: context)
    }

    var refreshInterval: TimeInterval { scheduler.interval }

    func storedCredentials(_ id: UUID) -> ProviderCredentials? {
        guard !isDemo, let record = registry.record(id) else { return nil }
        return try? credentials.load(record)
    }

    // MARK: - Connecting

    /// Checks the key with the provider, then saves it to the Keychain. With `id`, replaces that
    /// connection's key; without, adds a new connection. Returns the connection's id. Throws `SpendError`
    /// for the inline message. Empty secret fields keep the saved value, so replacing a team ID doesn't mean
    /// re-pasting a key.
    @discardableResult
    func connect(_ provider: ProviderID, replacing id: UUID? = nil, values: [String: String]) async throws -> UUID {
        var merged = values
        if let id, let existing = storedCredentials(id) {
            for field in provider.info.fields where (merged[field.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                if field.isSecret, let saved = existing[field.id] { merged[field.id] = saved }
            }
        }
        let candidate = ProviderCredentials(provider: provider, values: merged)
        guard candidate.missingFields.isEmpty else { throw SpendError.notConfigured }
        guard let adapter = providers[provider] else { throw SpendError.noUsageAPI }
        if !isDemo { try await adapter.validate(candidate, now: Date()) }
        var next = registry
        let record = id.flatMap { next.record($0) } ?? next.adding(provider, named: candidate["serviceName"])
        if !isDemo {
            // The record first, so a key is never saved under an id nothing knows about.
            Preferences.connections = next
            do {
                try credentials.save(candidate, for: record)
            } catch {
                if id == nil { Preferences.connections = registry }
                throw KeychainFailure()
            }
        }
        registry = next
        let floor = (try? CustomConfig(candidate))?.interval
        states[record.id] = ProviderState(provider: provider, connectionID: record.id, refreshFloor: floor)
        lastCapCheck[record.id] = nil
        scheduler.add(record.id, provider: provider, now: Date(), floor: floor)
        onChange?()
        tick()
        return record.id
    }

    struct KeychainFailure: Error, LocalizedError {
        var errorDescription: String? { "The key worked, but the Keychain wouldn't save it. Try again." }
    }

    func rename(_ id: UUID, to name: String) {
        registry.rename(id, to: name)
        if !isDemo { Preferences.connections = registry }
        onChange?()
    }

    func disconnect(_ id: UUID) throws {
        guard let record = registry.record(id) else { return }
        if !isDemo { try credentials.delete(record) }
        registry.remove(id)
        if !isDemo {
            Preferences.connections = registry
            var limits = Preferences.thresholds
            limits.perConnection[id] = nil
            Preferences.thresholds = limits
        }
        states[id] = nil
        scheduler.remove(id)
        saveCache()
        onChange?()
    }

    /// Deletes every key and all local data. For uninstalling.
    func removeEverything() throws {
        if !isDemo { try credentials.deleteAll(registry.records) }
        for record in registry.records { scheduler.remove(record.id) }
        registry = ConnectionRegistry()
        states = [:]
        audit = CapAuditState()
        SpendCache.delete()
        Preferences.allKeys.forEach(Preferences.defaults.removeObject(forKey:))
        onChange?()
    }

    // MARK: - Refreshing

    func refreshNow() {
        guard !isDemo else { return }
        scheduler.refreshAll(now: Date())
        tick()
    }

    /// Refresh pressed for one connection.
    func refresh(_ id: UUID) {
        guard !isDemo else { return }
        scheduler.refresh(id, now: Date())
        tick()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        Preferences.defaults.set(interval, forKey: Preferences.refreshIntervalKey)
        scheduler.setInterval(interval, now: Date())
        tick()
    }

    func sleep() {
        isAsleep = true
        scheduler.sleep()
        timer?.invalidate()
        onChange?()
    }

    func wake() {
        isAsleep = false
        lastWake = Date()
        scheduler.wake(now: Date())
        onChange?()
        tick()
    }

    private func setOnline(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        // Coming back online counts as fresh start for anything that failed while offline.
        if online { scheduler.refreshAll(now: Date()) }
        onChange?()
        tick()
    }

    /// Asks every provider that's due, then sets the timer for the next one.
    private func tick() {
        guard !isDemo else { return }
        timer?.invalidate()
        let now = Date()
        for id in scheduler.takeDue(now: now) {
            fetch(id)
        }
        isRefreshing = !inFlight.isEmpty
        if let next = scheduler.nextDue {
            let delay = max(1, next.timeIntervalSinceNow)
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func fetch(_ id: UUID) {
        guard let record = registry.record(id), let adapter = providers[record.provider] else { return }
        guard let stored = storedCredentials(id) else {
            scheduler.failed(id, error: .notConfigured, now: Date())
            states[id]?.record(.notConfigured, at: Date())
            return
        }
        inFlight.insert(id)
        let checkCaps = lastCapCheck[id].map { Date().timeIntervalSince($0) >= Self.capCheckInterval } ?? true
        Task {
            let result: Result<SpendSnapshot, SpendError>
            do {
                result = .success(try await adapter.fetchSpend(stored, now: Date()))
            } catch let error as SpendError {
                result = .failure(error)
            } catch {
                result = .failure(.network)
            }
            let verifications = checkCaps ? await adapter.verifyCaps(stored, now: Date()) : []
            finish(record, result: result, verifications: verifications, checkedCaps: checkCaps)
        }
    }

    private func finish(_ record: ConnectionRecord, result: Result<SpendSnapshot, SpendError>,
                        verifications: [CapVerification], checkedCaps: Bool) {
        let id = record.id
        inFlight.remove(id)
        // Disconnected while the request was out.
        guard registry.record(id) != nil else { return }
        let now = Date()
        let empty = ProviderState(provider: record.provider, connectionID: id, refreshFloor: customConfig(id)?.interval)
        switch result {
        case .success(let snapshot):
            states[id, default: empty].record(snapshot)
            scheduler.succeeded(id, now: now)
        case .failure(let error):
            states[id, default: empty].record(error, at: now)
            scheduler.failed(id, error: error, now: now)
        }
        if checkedCaps {
            lastCapCheck[id] = now
            if !verifications.isEmpty {
                audit.record(verifications)
                Preferences.capAudit = audit
            }
        }
        saveCache()
        if case .success = result { onSpend?(orderedStates) }
        onChange?()
        tick()
    }

    private func saveCache() {
        guard !isDemo else { return }
        SpendCache.save(orderedStates)
    }
}

// MARK: - Caps audit

extension SpendModel {
    func mark(_ capID: String, _ mark: CapAuditState.Mark?) {
        audit.mark(capID, mark)
        if !isDemo { Preferences.capAudit = audit }
        onChange?()
    }

    /// Asks the provider's API about its caps now, for providers that can say. With several connections,
    /// each is asked; the audit keeps one answer per cap, the last one read.
    func checkCaps(_ provider: ProviderID) async {
        guard !isDemo, let adapter = providers[provider] else { return }
        var results: [CapVerification] = []
        for record in registry.records(for: provider) {
            guard let stored = storedCredentials(record.id) else { continue }
            results += await adapter.verifyCaps(stored, now: Date())
            lastCapCheck[record.id] = Date()
        }
        audit.record(results)
        Preferences.capAudit = audit
        onChange?()
    }

    /// Providers the person uses: connected ones, plus any they've marked a cap for (Supabase has nothing to
    /// connect, so marking its cap is how it joins the audit).
    var auditProviders: [ProviderID] {
        ProviderID.allCases.filter { provider in
            guard !CapsCatalog.controls(for: provider).isEmpty else { return false }
            return connected.contains(provider)
                || CapsCatalog.controls(for: provider).contains { audit.marks[$0.id] != nil }
        }
    }

    var capsNeedingAttention: Int {
        auditProviders.reduce(0) { $0 + audit.progress(for: $1, now: Date()).needsAttention }
    }
}

// MARK: - What Settings shows

extension SpendModel {
    /// The light and line Settings shows for a connection.
    func status(_ id: UUID, isChecking: Bool = false, now: Date = Date()) -> ProviderStatus {
        guard let record = registry.record(id) else {
            return ProviderStatus(light: .off, label: "Not connected", line: "Not connected")
        }
        return ProviderStatus.of(record.provider, isConnected: true, state: states[id], freshness: freshness(id, now: now),
                                 isChecking: isChecking || inFlight.contains(id), now: now)
    }

    /// The status of a provider with no connection yet.
    func status(_ provider: ProviderID, isChecking: Bool = false) -> ProviderStatus {
        ProviderStatus.of(provider, isConnected: false, state: nil, freshness: .neverChecked, isChecking: isChecking)
    }

    /// What's saved for a connection, with secrets reduced to their last four characters.
    func keyHints(_ id: UUID) -> [(field: CredentialField, text: String)] {
        guard let record = registry.record(id) else { return [] }
        if isDemo {
            let fields = record.provider.info.fields.filter { !$0.isOptional }
            let sample = registry.records(for: record.provider).first?.id == id ? "Ending in 0001" : "Ending in 7d2c"
            return fields.map { ($0, $0.isSecret ? sample : "sample") }
        }
        return storedCredentials(id)?.hints ?? []
    }
}

// MARK: - Sample data

extension SpendModel {
    /// Sample connections and readings, for demo mode and the render tests. Demo models only.
    func showSample(registry: ConnectionRegistry, states: [ProviderState]) {
        guard isDemo else { return }
        self.registry = registry
        self.states = Dictionary(uniqueKeysWithValues: states.map { ($0.connectionID, $0) })
        onChange?()
    }
}
