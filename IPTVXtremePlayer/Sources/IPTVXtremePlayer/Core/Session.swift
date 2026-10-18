import Foundation

/// A live, authenticated connection to one provider, plus a cached content
/// repository. All content fetches go through here so caching and the in-memory
/// search index are shared across the UI.
final class Session {
    let profile: Profile
    let client: XtreamClient
    let userData: UserData
    let auth: AuthResponse
    private let cache: DataCache

    // In-memory indexes (populated lazily; used for search & favorite resolution).
    private(set) var allLive: [LiveStream] = []
    private(set) var allMovies: [VODStream] = []
    private(set) var allSeries: [SeriesStream] = []

    private let cacheTTL: TimeInterval = 6 * 3600

    init(profile: Profile, client: XtreamClient, auth: AuthResponse) {
        self.profile = profile
        self.client = client
        self.auth = auth
        self.userData = UserData(profileID: profile.id)
        self.cache = DataCache(namespace: profile.id.uuidString)
    }

    // MARK: Generic cached loader

    private func cached<T: Codable>(_ key: String, forceRefresh: Bool,
                                    fetch: () async throws -> T) async throws -> T {
        if !forceRefresh, let hit = cache.load(T.self, key: key, maxAge: cacheTTL) {
            return hit
        }
        do {
            let fresh = try await fetch()
            cache.save(fresh, key: key)
            return fresh
        } catch {
            // Fall back to any stale cache when the network fails.
            if let stale = cache.load(T.self, key: key, maxAge: nil) { return stale }
            throw error
        }
    }

    // MARK: Categories

    func liveCategories(forceRefresh: Bool = false) async throws -> [Category] {
        try await cached("live_cats", forceRefresh: forceRefresh) { try await self.client.liveCategories() }
    }
    func movieCategories(forceRefresh: Bool = false) async throws -> [Category] {
        try await cached("vod_cats", forceRefresh: forceRefresh) { try await self.client.vodCategories() }
    }
    func seriesCategories(forceRefresh: Bool = false) async throws -> [Category] {
        try await cached("series_cats", forceRefresh: forceRefresh) { try await self.client.seriesCategories() }
    }

    // MARK: Streams (full lists, indexed for search)

    func loadAllLive(forceRefresh: Bool = false) async throws -> [LiveStream] {
        let list = try await cached("live_all", forceRefresh: forceRefresh) { try await self.client.liveStreams() }
        allLive = list
        return list
    }
    func loadAllMovies(forceRefresh: Bool = false) async throws -> [VODStream] {
        let list = try await cached("vod_all", forceRefresh: forceRefresh) { try await self.client.vodStreams() }
        allMovies = list
        return list
    }
    func loadAllSeries(forceRefresh: Bool = false) async throws -> [SeriesStream] {
        let list = try await cached("series_all", forceRefresh: forceRefresh) { try await self.client.series() }
        allSeries = list
        return list
    }

    // MARK: Detail

    func vodInfo(_ id: Int) async throws -> VODInfo { try await client.vodInfo(streamID: id) }
    func seriesInfo(_ id: Int) async throws -> SeriesInfo { try await client.seriesInfo(seriesID: id) }

    // MARK: Search (across cached indexes)

    struct SearchResults {
        var live: [LiveStream]
        var movies: [VODStream]
        var series: [SeriesStream]
        var isEmpty: Bool { live.isEmpty && movies.isEmpty && series.isEmpty }
    }

    func search(_ query: String, limitPerSection: Int = 60) -> SearchResults {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return SearchResults(live: [], movies: [], series: []) }
        func matches(_ name: String) -> Bool { name.lowercased().contains(q) }
        return SearchResults(
            live: allLive.filter { matches($0.name) }.prefix(limitPerSection).map { $0 },
            movies: allMovies.filter { matches($0.name) }.prefix(limitPerSection).map { $0 },
            series: allSeries.filter { matches($0.name) }.prefix(limitPerSection).map { $0 }
        )
    }

    /// Warm the search indexes in the background after connecting.
    func warmIndexes() {
        Task.detached { [weak self] in
            _ = try? await self?.loadAllLive()
            _ = try? await self?.loadAllMovies()
            _ = try? await self?.loadAllSeries()
        }
    }

    func clearCaches() { cache.clear() }
}
