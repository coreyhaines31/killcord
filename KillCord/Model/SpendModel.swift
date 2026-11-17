import Foundation
import KillCordCore
import Network
import Observation

/// Owns the connected providers: reads their keys from the Keychain when it needs them, asks each
/// provider on the scheduler's timetable while the Mac is awake, and keeps the latest spend.
@MainActor
@Observable
final class SpendModel {
    private(set) var connected: [ProviderID] = []
    private(set) var states: [ProviderID: ProviderState] = [:]
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

    private let credentials: CredentialStore
    private let providers: [ProviderID: SpendProvider]
    @ObservationIgnored private var scheduler: RefreshScheduler
    @ObservationIgnored private var timer: Timer?
    /// Providers being asked right now.
    private(set) var inFlight: Set<ProviderID> = []
    @ObservationIgnored private var lastCapCheck: [ProviderID: Date] = [:]
    private let pathMonitor = NWPathMonitor()

    /// Cap settings change rarely; ask at most this often (plus on connect and on request).
    static let capCheckInterval: TimeInterval = 6 * 3600

    init(secrets: SecretStore = KeychainSecretStore(), http: HTTPClient = URLSessionHTTPClient(), isDemo: Bool = false) {
        credentials = CredentialStore(secrets: secrets)
        providers = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { ($0, SpendProviders.make($0, http: http)) })
        scheduler = RefreshScheduler(interval: Preferences.refreshInterval)
        self.isDemo = isDemo
        audit = isDemo ? DemoData.audit() : Preferences.capAudit
    }

    func start() {
        if isDemo {
            let demo = DemoData.states()
            connected = demo.map(\.provider)
            states = Dictionary(uniqueKeysWithValues: demo.map { ($0.provider, $0) })
            onChange?()
            return
        }
        connected = credentials.connected()
        let cached = SpendCache.load()
        for state in cached where connected.contains(state.provider) {
            states[state.provider] = state
        }
        for provider in connected {
            if states[provider] == nil { states[provider] = ProviderState(provider: provider) }
            scheduler.add(provider, now: Date())
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.setOnline(online) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "app.killcord.KillCord.path"))
        tick()
    }

    // MARK: - What the panel shows

    var freshnessContext: FreshnessContext {
        FreshnessContext(now: Date(), launchedAt: isDemo ? Date.distantPast : launchedAt, lastWake: lastWake,
                         isAsleep: isAsleep, isOnline: isOnline, interval: scheduler.interval)
    }

    func summary(now: Date = Date()) -> SpendSummary {
        var context = freshnessContext
        context.now = now
        return SpendSummary(states: connected.compactMap { states[$0] }, context: context)
    }

    func freshness(_ provider: ProviderID, now: Date = Date()) -> Freshness {
        guard let state = states[provider] else { return .neverChecked }
        var context = freshnessContext
        context.now = now
        return Freshness.of(state, context: context)
    }

    var refreshInterval: TimeInterval { scheduler.interval }

    func storedCredentials(_ provider: ProviderID) -> ProviderCredentials? {
        guard !isDemo else { return nil }
        return try? credentials.load(provider)
    }

    // MARK: - Connecting

    /// Checks the key with the provider, then saves it to the Keychain. Throws `SpendError` for the inline
    /// message. Empty secret fields keep the saved value, so replacing a team ID doesn't mean re-pasting a key.
    func connect(_ provider: ProviderID, values: [String: String]) async throws {
        var merged = values
        if let existing = storedCredentials(provider) {
            for field in provider.info.fields where (merged[field.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                if field.isSecret, let saved = existing[field.id] { merged[field.id] = saved }
            }
        }
        let candidate = ProviderCredentials(provider: provider, values: merged)
        guard candidate.missingFields.isEmpty else { throw SpendError.notConfigured }
        guard let adapter = providers[provider] else { throw SpendError.noUsageAPI }
        if !isDemo {
            try await adapter.validate(candidate, now: Date())
            do {
                try credentials.save(candidate)
            } catch {
                throw KeychainFailure()
            }
        }
        if !connected.contains(provider) { connected.append(provider) }
        connected.sort()
        states[provider] = ProviderState(provider: provider)
        lastCapCheck[provider] = nil
        scheduler.add(provider, now: Date())
        onChange?()
        tick()
    }

    struct KeychainFailure: Error, LocalizedError {
        var errorDescription: String? { "The key worked, but the Keychain wouldn't save it. Try again." }
    }

    func disconnect(_ provider: ProviderID) throws {
        if !isDemo { try credentials.delete(provider) }
        connected.removeAll { $0 == provider }
        states[provider] = nil
        scheduler.remove(provider)
        saveCache()
        onChange?()
    }

    /// Deletes every key and all local data. For uninstalling.
    func removeEverything() throws {
        for provider in ProviderID.allCases where !isDemo {
            try credentials.delete(provider)
        }
        for provider in connected { scheduler.remove(provider) }
        connected = []
        states = [:]
        audit = CapAuditState()
        SpendCache.delete()
        Preferences.allKeys.forEach(UserDefaults.standard.removeObject(forKey:))
        onChange?()
    }

    // MARK: - Refreshing

    func refreshNow() {
        guard !isDemo else { return }
        scheduler.refreshAll(now: Date())
        tick()
    }

    /// Refresh pressed for one provider.
    func refresh(_ provider: ProviderID) {
        guard !isDemo else { return }
        scheduler.refresh(provider, now: Date())
        tick()
    }

    func setRefreshInterval(_ interval: TimeInterval) {
        UserDefaults.standard.set(interval, forKey: Preferences.refreshIntervalKey)
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
        for provider in scheduler.takeDue(now: now) {
            fetch(provider)
        }
        isRefreshing = !inFlight.isEmpty
        if let next = scheduler.nextDue {
            let delay = max(1, next.timeIntervalSinceNow)
            timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func fetch(_ provider: ProviderID) {
        guard let adapter = providers[provider] else { return }
        guard let stored = storedCredentials(provider) else {
            scheduler.failed(provider, error: .notConfigured, now: Date())
            states[provider]?.record(.notConfigured, at: Date())
            return
        }
        inFlight.insert(provider)
        let checkCaps = lastCapCheck[provider].map { Date().timeIntervalSince($0) >= Self.capCheckInterval } ?? true
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
            finish(provider, result: result, verifications: verifications, checkedCaps: checkCaps)
        }
    }

    private func finish(_ provider: ProviderID, result: Result<SpendSnapshot, SpendError>,
                        verifications: [CapVerification], checkedCaps: Bool) {
        inFlight.remove(provider)
        // Disconnected while the request was out.
        guard connected.contains(provider) else { return }
        let now = Date()
        switch result {
        case .success(let snapshot):
            states[provider, default: ProviderState(provider: provider)].record(snapshot)
            scheduler.succeeded(provider, now: now)
        case .failure(let error):
            states[provider, default: ProviderState(provider: provider)].record(error, at: now)
            scheduler.failed(provider, error: error, now: now)
        }
        if checkedCaps {
            lastCapCheck[provider] = now
            if !verifications.isEmpty {
                audit.record(verifications)
                Preferences.capAudit = audit
            }
        }
        saveCache()
        if case .success = result { onSpend?(connected.compactMap { states[$0] }) }
        onChange?()
        tick()
    }

    private func saveCache() {
        guard !isDemo else { return }
        SpendCache.save(connected.compactMap { states[$0] })
    }

    // MARK: - Caps audit

    func mark(_ capID: String, _ mark: CapAuditState.Mark?) {
        audit.mark(capID, mark)
        if !isDemo { Preferences.capAudit = audit }
        onChange?()
    }

    /// Asks the provider's API about its caps now, for providers that can say.
    func checkCaps(_ provider: ProviderID) async {
        guard !isDemo, let adapter = providers[provider], let stored = storedCredentials(provider) else { return }
        let results = await adapter.verifyCaps(stored, now: Date())
        lastCapCheck[provider] = Date()
        audit.record(results)
        Preferences.capAudit = audit
        onChange?()
    }

    /// Providers the person uses: connected ones, plus any they've marked a cap for (Supabase has nothing to
    /// connect, so marking its cap is how it joins the audit).
    var auditProviders: [ProviderID] {
        ProviderID.allCases.filter { provider in
            connected.contains(provider)
                || CapsCatalog.controls(for: provider).contains { audit.marks[$0.id] != nil }
        }
    }

    var capsNeedingAttention: Int {
        auditProviders.reduce(0) { $0 + audit.progress(for: $1, now: Date()).needsAttention }
    }
}

// MARK: - What Settings shows

extension SpendModel {
    /// The light and line Settings shows for a provider.
    func status(_ provider: ProviderID, isChecking: Bool = false, now: Date = Date()) -> ProviderStatus {
        ProviderStatus.of(provider, isConnected: connected.contains(provider), state: states[provider],
                          freshness: freshness(provider, now: now),
                          isChecking: isChecking || inFlight.contains(provider), now: now)
    }

    /// What's saved for a provider, with secrets reduced to their last four characters.
    func keyHints(_ provider: ProviderID) -> [(field: CredentialField, text: String)] {
        if isDemo {
            return provider.info.fields.filter { !$0.isOptional }.map { ($0, $0.isSecret ? "Sample key" : "sample") }
        }
        return storedCredentials(provider)?.hints ?? []
    }
}
