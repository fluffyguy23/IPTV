import Foundation

// MARK: - Auth / account

struct AuthResponse: Decodable {
    let userInfo: UserInfo?
    let serverInfo: ServerInfo?

    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
        case serverInfo = "server_info"
    }
}

struct UserInfo: Decodable {
    let username: String?
    let status: String?         // "Active", "Expired", "Banned", "Disabled"
    let auth: Int?              // 1 when authenticated
    let expDate: Date?         // subscription expiry
    let isTrial: Bool?
    let activeConnections: Int?
    let maxConnections: Int?
    let allowedOutputFormats: [String]?
    let createdAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.lenientString(.username)
        status = c.lenientString(.status)
        auth = c.lenientInt(.auth)
        expDate = c.lenientInt(.expDate).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        isTrial = c.lenientBool(.isTrial)
        activeConnections = c.lenientInt(.activeConnections)
        maxConnections = c.lenientInt(.maxConnections)
        allowedOutputFormats = c.lenientStringArray(.allowedOutputFormats)
        createdAt = c.lenientInt(.createdAt).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    enum CodingKeys: String, CodingKey {
        case username, status, auth
        case expDate = "exp_date"
        case isTrial = "is_trial"
        case activeConnections = "active_cons"
        case maxConnections = "max_connections"
        case allowedOutputFormats = "allowed_output_formats"
        case createdAt = "created_at"
    }
}

struct ServerInfo: Decodable {
    let url: String?
    let port: String?
    let httpsPort: String?
    let serverProtocol: String?
    let timezone: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = c.lenientString(.url)
        port = c.lenientString(.port)
        httpsPort = c.lenientString(.httpsPort)
        serverProtocol = c.lenientString(.serverProtocol)
        timezone = c.lenientString(.timezone)
    }

    enum CodingKeys: String, CodingKey {
        case url, port, timezone
        case httpsPort = "https_port"
        case serverProtocol = "server_protocol"
    }
}

// MARK: - Categories

struct Category: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let parentID: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        name = c.lenientString(.name) ?? "Unknown"
        parentID = c.lenientString(.parentID)
    }

    init(id: String, name: String) {
        self.id = id; self.name = name; self.parentID = nil
    }

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name = "category_name"
        case parentID = "parent_id"
    }
}

// MARK: - Live channels

struct LiveStream: Codable, Identifiable, Hashable {
    let streamID: Int
    let num: Int?
    let name: String
    let icon: String?
    let epgChannelID: String?
    let categoryID: String?
    let tvArchive: Bool
    let addedTimestamp: Int?

    var id: Int { streamID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamID = c.lenientInt(.streamID) ?? 0
        num = c.lenientInt(.num)
        name = (c.lenientString(.name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        icon = c.lenientString(.icon)
        epgChannelID = c.lenientString(.epgChannelID)
        categoryID = c.lenientString(.categoryID)
        tvArchive = (c.lenientInt(.tvArchive) ?? 0) > 0
        addedTimestamp = c.lenientInt(.addedTimestamp)
    }

    enum CodingKeys: String, CodingKey {
        case num, name
        case addedTimestamp = "added"
        case streamID = "stream_id"
        case icon = "stream_icon"
        case epgChannelID = "epg_channel_id"
        case categoryID = "category_id"
        case tvArchive = "tv_archive"
    }
}

// MARK: - Movies (VOD)

struct VODStream: Codable, Identifiable, Hashable {
    let streamID: Int
    let num: Int?
    let name: String
    let icon: String?
    let rating5: Double?
    let categoryID: String?
    let containerExtension: String?
    let addedTimestamp: Int?

    var id: Int { streamID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamID = c.lenientInt(.streamID) ?? 0
        num = c.lenientInt(.num)
        name = (c.lenientString(.name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        icon = c.lenientString(.icon)
        rating5 = c.lenientDouble(.rating5)
        categoryID = c.lenientString(.categoryID)
        containerExtension = c.lenientString(.containerExtension)
        addedTimestamp = c.lenientInt(.addedTimestamp)
    }

    enum CodingKeys: String, CodingKey {
        case num, name
        case addedTimestamp = "added"
        case streamID = "stream_id"
        case icon = "stream_icon"
        case rating5 = "rating_5based"
        case categoryID = "category_id"
        case containerExtension = "container_extension"
    }
}

/// Full detail for a single movie (get_vod_info).
struct VODInfo: Decodable {
    let name: String?
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let durationSecs: Int?
    let posterPath: String?
    let backdrops: [String]?
    let youtubeTrailer: String?
    let containerExtension: String?
    let streamID: Int?

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let info = try? root.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        name = info?.lenientString(.name)
        plot = info?.lenientString(.plot) ?? info?.lenientString(.description)
        cast = info?.lenientString(.cast)
        director = info?.lenientString(.director)
        genre = info?.lenientString(.genre)
        releaseDate = info?.lenientString(.releaseDate) ?? info?.lenientString(.releasedate)
        rating = info?.lenientString(.rating)
        durationSecs = info?.lenientInt(.durationSecs)
        posterPath = info?.lenientString(.movieImage) ?? info?.lenientString(.coverBig)
        backdrops = info?.lenientStringArray(.backdropPath)
        youtubeTrailer = info?.lenientString(.youtubeTrailer)

        let movieData = try? root.nestedContainer(keyedBy: MovieDataKeys.self, forKey: .movieData)
        containerExtension = movieData?.lenientString(.containerExtension)
        streamID = movieData?.lenientInt(.streamID)
    }

    enum RootKeys: String, CodingKey { case info, movieData = "movie_data" }
    enum InfoKeys: String, CodingKey {
        case name, plot, description, cast, director, genre, rating
        case releaseDate = "release_date"
        case releasedate
        case durationSecs = "duration_secs"
        case movieImage = "movie_image"
        case coverBig = "cover_big"
        case backdropPath = "backdrop_path"
        case youtubeTrailer = "youtube_trailer"
    }
    enum MovieDataKeys: String, CodingKey {
        case streamID = "stream_id"
        case containerExtension = "container_extension"
    }
}

// MARK: - Series

struct SeriesStream: Codable, Identifiable, Hashable {
    let seriesID: Int
    let name: String
    let cover: String?
    let plot: String?
    let genre: String?
    let cast: String?
    let director: String?
    let releaseDate: String?
    let rating5: Double?
    let categoryID: String?
    let lastModified: Int?

    var id: Int { seriesID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        seriesID = c.lenientInt(.seriesID) ?? 0
        name = (c.lenientString(.name) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        cover = c.lenientString(.cover)
        plot = c.lenientString(.plot)
        genre = c.lenientString(.genre)
        cast = c.lenientString(.cast)
        director = c.lenientString(.director)
        releaseDate = c.lenientString(.releaseDate)
        rating5 = c.lenientDouble(.rating5)
        categoryID = c.lenientString(.categoryID)
        lastModified = c.lenientInt(.lastModified)
    }

    enum CodingKeys: String, CodingKey {
        case name, cover, plot, genre, cast, director
        case seriesID = "series_id"
        case releaseDate = "releaseDate"
        case rating5 = "rating_5based"
        case categoryID = "category_id"
        case lastModified = "last_modified"
    }
}

struct Episode: Decodable, Identifiable, Hashable {
    let id: String
    let episodeNum: Int
    let title: String
    let containerExtension: String?
    let plot: String?
    let durationSecs: Int?
    let image: String?
    let season: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        episodeNum = c.lenientInt(.episodeNum) ?? 0
        title = (c.lenientString(.title) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        containerExtension = c.lenientString(.containerExtension)
        season = c.lenientInt(.season) ?? 0
        let info = try? c.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        plot = info?.lenientString(.plot)
        durationSecs = info?.lenientInt(.durationSecs)
        image = info?.lenientString(.movieImage)
    }

    enum CodingKeys: String, CodingKey {
        case id, title, season, info
        case episodeNum = "episode_num"
        case containerExtension = "container_extension"
    }
    enum InfoKeys: String, CodingKey {
        case plot
        case durationSecs = "duration_secs"
        case movieImage = "movie_image"
    }
}

/// get_series_info: series metadata + episodes grouped by season.
struct SeriesInfo: Decodable {
    let plot: String?
    let cast: String?
    let director: String?
    let genre: String?
    let releaseDate: String?
    let rating: String?
    let cover: String?
    /// Season number -> ordered episodes.
    let episodesBySeason: [Int: [Episode]]

    var sortedSeasons: [Int] { episodesBySeason.keys.sorted() }

    init(from decoder: Decoder) throws {
        let root = try decoder.container(keyedBy: RootKeys.self)
        let info = try? root.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
        plot = info?.lenientString(.plot)
        cast = info?.lenientString(.cast)
        director = info?.lenientString(.director)
        genre = info?.lenientString(.genre)
        releaseDate = info?.lenientString(.releaseDate)
        rating = info?.lenientString(.rating)
        cover = info?.lenientString(.cover)

        // "episodes": { "1": [ {..}, {..} ], "2": [ ... ] }
        var grouped: [Int: [Episode]] = [:]
        if let epContainer = try? root.nestedContainer(keyedBy: DynamicKey.self, forKey: .episodes) {
            for key in epContainer.allKeys {
                let season = Int(key.stringValue) ?? 0
                if let eps = try? epContainer.decode([Episode].self, forKey: key) {
                    grouped[season] = eps.sorted { $0.episodeNum < $1.episodeNum }
                }
            }
        }
        episodesBySeason = grouped
    }

    enum RootKeys: String, CodingKey { case info, episodes }
    enum InfoKeys: String, CodingKey {
        case plot, cast, director, genre, rating, cover
        case releaseDate = "releaseDate"
    }
    struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }
}

// MARK: - EPG

struct EPGEntry: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let start: Date?
    let end: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        title = EPGEntry.decodeBase64(c.lenientString(.title))
        description = EPGEntry.decodeBase64(c.lenientString(.description))
        start = c.lenientInt(.startTimestamp).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        end = c.lenientInt(.stopTimestamp).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Xtream base64-encodes EPG title/description.
    static func decodeBase64(_ s: String?) -> String {
        guard let s = s, !s.isEmpty else { return "" }
        if let data = Data(base64Encoded: s), let decoded = String(data: data, encoding: .utf8) {
            return decoded
        }
        return s
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case startTimestamp = "start_timestamp"
        case stopTimestamp = "stop_timestamp"
    }
}

struct EPGResponse: Decodable {
    let listings: [EPGEntry]
    enum CodingKeys: String, CodingKey { case listings = "epg_listings" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listings = (try? c.decode([EPGEntry].self, forKey: .listings)) ?? []
    }
}
