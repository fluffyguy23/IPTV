import Foundation

extension Notification.Name {
    static let userDataChanged = Notification.Name("userDataChanged")
}

/// Per-profile favorites, watch history (with resume points), and recent
/// channels. Persisted as JSON under Application Support/UserData/<profileID>.json.
final class UserData {
    private struct Store: Codable {
        var favorites: [MediaRef] = []
        var history: [HistoryEntry] = []
        var recentChannels: [Int] = []
    }

    private let fileURL: URL
    private var store: Store {
        didSet { persist(); NotificationCenter.default.post(name: .userDataChanged, object: nil) }
    }

    init(profileID: UUID) {
        let dir = AppPaths.subdirectory("UserData")
        fileURL = dir.appendingPathComponent("\(profileID.uuidString).json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            store = decoded
        } else {
            store = Store()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Favorites

    var favorites: [MediaRef] { store.favorites }

    func isFavorite(_ ref: MediaRef) -> Bool {
        store.favorites.contains { $0.key == ref.key }
    }

    @discardableResult
    func toggleFavorite(_ ref: MediaRef) -> Bool {
        if let idx = store.favorites.firstIndex(where: { $0.key == ref.key }) {
            store.favorites.remove(at: idx)
            return false
        } else {
            store.favorites.insert(ref, at: 0)
            return true
        }
    }

    func favorites(of kind: MediaRef.Kind) -> [MediaRef] {
        store.favorites.filter { $0.kind == kind }
    }

    // MARK: History & resume

    var history: [HistoryEntry] { store.history.sorted { $0.lastPlayed > $1.lastPlayed } }

    /// Items worth resuming on the Home screen (unfinished movies/episodes).
    func continueWatching(limit: Int = 20) -> [HistoryEntry] {
        history.filter { $0.ref.isResumable && !$0.isFinished && $0.positionSecs > 10 }
            .prefix(limit).map { $0 }
    }

    func resumePosition(for ref: MediaRef) -> Double {
        guard let e = store.history.first(where: { $0.ref.key == ref.key }), !e.isFinished else { return 0 }
        return e.positionSecs
    }

    /// Record that playback started (updates recents; seeds a history row).
    func recordPlay(_ ref: MediaRef) {
        if ref.kind == .live, let sid = ref.streamID {
            store.recentChannels.removeAll { $0 == sid }
            store.recentChannels.insert(sid, at: 0)
            if store.recentChannels.count > 40 { store.recentChannels.removeLast() }
        }
        if let idx = store.history.firstIndex(where: { $0.ref.key == ref.key }) {
            store.history[idx].lastPlayed = Date()
            store.history[idx].ref = ref
        } else {
            store.history.insert(HistoryEntry(ref: ref, positionSecs: 0, durationSecs: 0, lastPlayed: Date()), at: 0)
        }
        trimHistory()
    }

    /// Update resume position during playback (called periodically).
    func updateProgress(_ ref: MediaRef, position: Double, duration: Double) {
        guard ref.isResumable else { return }
        if let idx = store.history.firstIndex(where: { $0.ref.key == ref.key }) {
            store.history[idx].positionSecs = position
            if duration > 0 { store.history[idx].durationSecs = duration }
            store.history[idx].lastPlayed = Date()
        } else {
            store.history.insert(HistoryEntry(ref: ref, positionSecs: position,
                                              durationSecs: duration, lastPlayed: Date()), at: 0)
        }
    }

    var recentChannelIDs: [Int] { store.recentChannels }

    /// Remove a single item from history (and recent channels), including its
    /// saved resume/progress. Does not touch favorites or the playlist itself.
    func removeHistory(_ ref: MediaRef) {
        store.history.removeAll { $0.ref.key == ref.key }
        if ref.kind == .live, let sid = ref.streamID {
            store.recentChannels.removeAll { $0 == sid }
        }
    }

    /// Remove a specific recent channel by stream id.
    func removeRecentChannel(_ streamID: Int) {
        store.recentChannels.removeAll { $0 == streamID }
    }

    func clearHistory() {
        store.history.removeAll()
        store.recentChannels.removeAll()
    }

    private func trimHistory() {
        if store.history.count > 200 {
            store.history = Array(history.prefix(200))
        }
    }
}
