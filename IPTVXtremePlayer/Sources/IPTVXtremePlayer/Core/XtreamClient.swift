import Foundation

/// Talks to the Xtream Codes `player_api.php` endpoint and builds stream URLs.
/// Networking is async; identical in-flight GETs are coalesced to avoid
/// duplicate requests (e.g. when several views load the same category at once).
final class XtreamClient {
    let baseURL: String
    let username: String
    private let password: String
    private let session: URLSession

    /// Base used for building stream URLs. Many providers answer the API on one
    /// port (e.g. 80) but serve streams on the port advertised in server_info
    /// (e.g. 8080). Defaults to baseURL until resolveStreamBase runs after auth.
    private(set) var streamBase: String

    private let lock = NSLock()
    private var inFlight: [String: Task<Data, Error>] = [:]

    init(baseURL: String, username: String, password: String) {
        self.baseURL = baseURL
        self.streamBase = baseURL
        self.username = username
        self.password = password
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    convenience init?(profile: Profile) {
        guard let password = ProfileStore.shared.password(for: profile) else { return nil }
        self.init(baseURL: profile.baseURL, username: profile.username, password: password)
    }

    // MARK: - URL building

    private func apiURL(action: String?, extra: [String: String] = [:]) -> URL? {
        guard var comps = URLComponents(string: baseURL + "/player_api.php") else { return nil }
        var items = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action = action { items.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in extra { items.append(URLQueryItem(name: k, value: v)) }
        comps.queryItems = items
        return comps.url
    }

    private func pathEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    /// Derive the stream base from server_info: keep the host (and scheme) the
    /// user connected to, but use the provider-advertised port for streams.
    func resolveStreamBase(from server: ServerInfo?) {
        guard let server = server,
              let comps = URLComponents(string: baseURL),
              let host = comps.host else { streamBase = baseURL; return }
        let scheme = comps.scheme ?? "http"
        let advertised = (scheme == "https" ? (server.httpsPort ?? server.port) : server.port)
        if let port = advertised, !port.isEmpty, port != "0" {
            streamBase = "\(scheme)://\(host):\(port)"
        } else if let p = comps.port {
            streamBase = "\(scheme)://\(host):\(p)"
        } else {
            streamBase = "\(scheme)://\(host)"
        }
        Log.info("Stream base resolved to \(Log.redact(streamBase))")
    }

    /// Live stream playback URL. `format` is "ts" or "m3u8".
    func liveURL(streamID: Int, format: String) -> URL? {
        URL(string: "\(streamBase)/live/\(pathEncode(username))/\(pathEncode(password))/\(streamID).\(format)")
    }

    /// Movie (VOD) playback URL.
    func movieURL(streamID: Int, ext: String) -> URL? {
        let e = ext.isEmpty ? "mp4" : ext
        return URL(string: "\(streamBase)/movie/\(pathEncode(username))/\(pathEncode(password))/\(streamID).\(e)")
    }

    /// Series episode playback URL.
    func episodeURL(episodeID: String, ext: String) -> URL? {
        let e = ext.isEmpty ? "mp4" : ext
        return URL(string: "\(streamBase)/series/\(pathEncode(username))/\(pathEncode(password))/\(episodeID).\(e)")
    }

    // MARK: - Core fetch (with de-duplication)

    // Synchronous (non-async) lock helpers so the NSLock is never held across a
    // suspension point.
    private func existingTask(for key: String) -> Task<Data, Error>? {
        lock.lock(); defer { lock.unlock() }
        return inFlight[key]
    }
    private func setTask(_ task: Task<Data, Error>?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        inFlight[key] = task
    }

    private func fetch(_ url: URL?) async throws -> Data {
        guard let url = url else { throw XtreamError.invalidURL }
        let key = url.absoluteString

        if let existing = existingTask(for: key) {
            return try await existing.value
        }
        let task = Task<Data, Error> { [session] in
            do {
                var req = URLRequest(url: url)
                req.setValue("IPTVXtremePlayer/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    throw XtreamError.httpStatus(http.statusCode)
                }
                return data
            } catch let e as XtreamError {
                throw e
            } catch let e as URLError where e.code == .timedOut {
                throw XtreamError.timeout
            } catch {
                throw XtreamError.network(error.localizedDescription)
            }
        }
        setTask(task, for: key)
        defer { setTask(nil, for: key) }
        return try await task.value
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty { throw XtreamError.empty }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Log.error("Decode failed for \(T.self): \(error)")
            throw XtreamError.malformedResponse
        }
    }

    // MARK: - Public API

    /// Authenticate and return account info. Throws for bad credentials,
    /// expired/banned subscriptions, or unreachable servers.
    @discardableResult
    func authenticate() async throws -> AuthResponse {
        let data = try await fetch(apiURL(action: nil))
        let auth = try decode(AuthResponse.self, from: data)
        guard let user = auth.userInfo else { throw XtreamError.malformedResponse }
        if let authFlag = user.auth, authFlag == 0 { throw XtreamError.authFailed }
        switch (user.status ?? "").lowercased() {
        case "expired": throw XtreamError.subscriptionExpired
        case "banned", "disabled": throw XtreamError.subscriptionBanned
        default: break
        }
        // Some servers omit auth flag but still return a username on success.
        if user.auth == nil && (user.username == nil || user.username?.isEmpty == true) {
            throw XtreamError.authFailed
        }
        return auth
    }

    func liveCategories() async throws -> [Category] {
        try decode([Category].self, from: await fetch(apiURL(action: "get_live_categories")))
    }
    func vodCategories() async throws -> [Category] {
        try decode([Category].self, from: await fetch(apiURL(action: "get_vod_categories")))
    }
    func seriesCategories() async throws -> [Category] {
        try decode([Category].self, from: await fetch(apiURL(action: "get_series_categories")))
    }

    func liveStreams(categoryID: String? = nil) async throws -> [LiveStream] {
        let extra = categoryID.map { ["category_id": $0] } ?? [:]
        return try decode([LiveStream].self, from: await fetch(apiURL(action: "get_live_streams", extra: extra)))
    }
    func vodStreams(categoryID: String? = nil) async throws -> [VODStream] {
        let extra = categoryID.map { ["category_id": $0] } ?? [:]
        return try decode([VODStream].self, from: await fetch(apiURL(action: "get_vod_streams", extra: extra)))
    }
    func series(categoryID: String? = nil) async throws -> [SeriesStream] {
        let extra = categoryID.map { ["category_id": $0] } ?? [:]
        return try decode([SeriesStream].self, from: await fetch(apiURL(action: "get_series", extra: extra)))
    }

    func vodInfo(streamID: Int) async throws -> VODInfo {
        try decode(VODInfo.self, from: await fetch(apiURL(action: "get_vod_info", extra: ["vod_id": String(streamID)])))
    }
    func seriesInfo(seriesID: Int) async throws -> SeriesInfo {
        try decode(SeriesInfo.self, from: await fetch(apiURL(action: "get_series_info", extra: ["series_id": String(seriesID)])))
    }

    func shortEPG(streamID: Int, limit: Int = 8) async throws -> [EPGEntry] {
        let extra = ["stream_id": String(streamID), "limit": String(limit)]
        let data = try await fetch(apiURL(action: "get_short_epg", extra: extra))
        return (try? decode(EPGResponse.self, from: data))?.listings ?? []
    }
}
