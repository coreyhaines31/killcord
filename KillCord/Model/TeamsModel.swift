import Foundation
import KillCordCore
import Observation

/// The Settings pane's view of a `TeamsSession`. Only built when the Teams flag is on.
@MainActor
@Observable
final class TeamsModel {
    private(set) var state: TeamsState = .signedOut
    private(set) var selectedWorkspaceID: String?
    private(set) var spend: TeamsMySpend?
    private(set) var spendError: String?
    @ObservationIgnored let session: TeamsSession
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    init(session: TeamsSession) {
        self.session = session
        session.onChange = { [weak self] in self?.sync() }
        sync()
    }

    private func sync() {
        state = session.state
        selectedWorkspaceID = session.selectedWorkspaceID
        spend = session.spend
    }

    func resume() {
        Task {
            await session.resume()
            await refreshSpend()
        }
    }

    func signIn(deviceName: String) {
        signInTask?.cancel()
        signInTask = Task {
            await session.signIn(deviceName: deviceName)
            await refreshSpend()
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        session.cancelSignIn()
    }

    func select(_ workspaceID: String) {
        session.select(workspaceID: workspaceID)
        Task { await refreshSpend() }
    }

    func refreshSpend() async {
        guard case .signedIn = session.state else { return }
        spendError = await session.loadSpend()?.errorDescription
        sync()
    }

    func signOut() {
        Task { await session.signOut() }
    }
}
