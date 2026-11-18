// The Mac's Teams sign-in as a small state machine, kept free of UI so it runs in tests on Linux:
// signed out -> showing a code -> signed in (workspaces, a chosen workspace, My spend), with errors inline.
import Foundation

public enum TeamsState: Sendable, Equatable {
    case signedOut
    case startingSignIn
    /// Show `userCode` and offer to open `verificationURIComplete` in the browser.
    case showingCode(DeviceSignIn)
    case signedIn(TeamsMe)
    case failed(TeamsError)
}

@MainActor
public final class TeamsSession {
    public private(set) var state: TeamsState = .signedOut
    public private(set) var selectedWorkspaceID: String?
    public private(set) var spend: TeamsMySpend?
    public var onChange: (() -> Void)?
    /// Bumped by every sign-in and cancel, so an older polling loop can't act on a newer attempt's state.
    private var attempt = 0

    public let settings: TeamsSettings
    private let client: TeamsClient
    private let defaults: UserDefaults
    private let sleep: @Sendable (TimeInterval) async -> Void
    private let now: @Sendable () -> Date

    /// Nil when the flag is off: with Teams off, nothing in this file is ever constructed.
    public static func makeIfEnabled(defaults: UserDefaults, http: HTTPClient, store: SecretStore) -> TeamsSession? {
        let settings = TeamsSettings.load(from: defaults)
        guard settings.isEnabled else { return nil }
        let client = TeamsClient(baseURL: settings.baseURL, http: http, tokens: TeamsTokenStore(store: store))
        return TeamsSession(settings: settings, client: client, defaults: defaults)
    }

    public init(settings: TeamsSettings, client: TeamsClient, defaults: UserDefaults,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.settings = settings
        self.client = client
        self.defaults = defaults
        self.sleep = sleep
        self.now = now
        selectedWorkspaceID = defaults.string(forKey: TeamsSettings.selectedWorkspaceKey)
    }

    private func set(_ state: TeamsState) {
        self.state = state
        onChange?()
    }

    /// On launch: if this Mac already has a token, load who it belongs to.
    public func resume() async {
        guard settings.isEnabled, client.isSignedIn else { return }
        await loadMe()
    }

    /// Asks the server for a code, then waits (polling at the server's interval) until the person approves
    /// or denies it in the browser, or the code expires.
    public func signIn(deviceName: String) async {
        guard settings.isEnabled else { return set(.failed(.disabled)) }
        attempt += 1
        let mine = attempt
        set(.startingSignIn)
        let signIn: DeviceSignIn
        do {
            signIn = try await client.startSignIn(deviceName: deviceName, now: now())
        } catch {
            guard mine == attempt else { return }
            return set(.failed(error as? TeamsError ?? .network))
        }
        guard mine == attempt else { return }
        set(.showingCode(signIn))
        while now() < signIn.expiresAt {
            await sleep(signIn.interval)
            guard mine == attempt, case .showingCode = state else { return }
            do {
                if try await client.pollToken(deviceCode: signIn.deviceCode) == .signedIn {
                    return await loadMe()
                }
            } catch {
                guard mine == attempt else { return }
                return set(.failed(error as? TeamsError ?? .network))
            }
        }
        guard mine == attempt else { return }
        set(.failed(.expired))
    }

    public func cancelSignIn() {
        attempt += 1
        if case .showingCode = state { set(.signedOut) }
    }

    private func loadMe() async {
        do {
            let account = try await client.me()
            if selectedWorkspaceID.map({ id in !account.workspaces.contains { $0.id == id } }) ?? true {
                selectedWorkspaceID = (account.workspaces.first { !$0.personal } ?? account.workspaces.first)?.id
                persistSelection()
            }
            set(.signedIn(account))
        } catch TeamsError.signedOut {
            set(.signedOut)
        } catch {
            set(.failed(error as? TeamsError ?? .network))
        }
    }

    public func select(workspaceID: String) {
        guard case .signedIn(let account) = state,
              account.workspaces.contains(where: { $0.id == workspaceID }) else { return }
        selectedWorkspaceID = workspaceID
        spend = nil
        persistSelection()
        onChange?()
    }

    private func persistSelection() {
        defaults.set(selectedWorkspaceID, forKey: TeamsSettings.selectedWorkspaceKey)
    }

    /// Your own spend in the chosen workspace. Errors leave the last good figures and say what went wrong.
    @discardableResult
    public func loadSpend(month: String? = nil) async -> TeamsError? {
        guard case .signedIn = state, let id = selectedWorkspaceID else { return .signedOut }
        do {
            spend = try await client.mySpend(workspaceID: id, month: month)
            onChange?()
            return nil
        } catch TeamsError.signedOut {
            set(.signedOut)
            return .signedOut
        } catch {
            return error as? TeamsError ?? .network
        }
    }

    public func signOut() async {
        await client.signOut()
        spend = nil
        set(.signedOut)
    }
}
