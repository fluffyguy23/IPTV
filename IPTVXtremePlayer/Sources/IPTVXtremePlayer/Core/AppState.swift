import Foundation

extension Notification.Name {
    static let sessionChanged = Notification.Name("sessionChanged")
}

/// Global app state: the current connected session (if any). UI observes
/// `.sessionChanged` to switch between the connection screen and the library.
@MainActor
final class AppState {
    static let shared = AppState()
    private init() {}

    private(set) var session: Session?
    var isConnected: Bool { session != nil }

    /// Authenticate against a profile (reads its stored password) and install the session.
    func connect(profile: Profile) async throws {
        guard let client = XtreamClient(profile: profile) else { throw XtreamError.authFailed }
        try await finishConnect(profile: profile, client: client)
    }

    /// Authenticate using an already-fetched password — avoids a second
    /// credential read and lets the caller read it off the main thread.
    func connect(profile: Profile, password: String) async throws {
        let client = XtreamClient(baseURL: profile.baseURL, username: profile.username, password: password)
        try await finishConnect(profile: profile, client: client)
    }

    private func finishConnect(profile: Profile, client: XtreamClient) async throws {
        let auth = try await client.authenticate()
        // Streams may live on the provider-advertised port even when the API
        // answers elsewhere (e.g. API on :80, streams on :8080).
        client.resolveStreamBase(from: auth.serverInfo)
        let session = Session(profile: profile, client: client, auth: auth)
        self.session = session
        ProfileStore.shared.lastUsedID = profile.id
        session.warmIndexes()
        NotificationCenter.default.post(name: .sessionChanged, object: nil)
    }

    func disconnect() {
        session = nil
        ProfileStore.shared.lastUsedID = nil
        NotificationCenter.default.post(name: .sessionChanged, object: nil)
    }
}
