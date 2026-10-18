import Foundation

/// A saved IPTV connection. The password is NOT stored here — it lives in the
/// Keychain keyed by `id`. Everything in this struct is non-secret metadata.
struct Profile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Normalized base URL, e.g. "http://host:port" (no trailing slash).
    var baseURL: String
    var username: String
    /// Preferred live container: "ts" or "m3u8".
    var liveFormat: String
    /// Optional user-supplied XMLTV EPG URL (overrides provider EPG when set).
    var xmltvURL: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, baseURL: String, username: String,
         liveFormat: String = "ts", xmltvURL: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.username = username
        self.liveFormat = liveFormat
        self.xmltvURL = xmltvURL
        self.createdAt = createdAt
    }
}

enum URLNormalizer {
    /// Turn user input into "scheme://host[:port]" with no trailing slash or path.
    /// Accepts "host", "host:8080", "http://host/", "https://host:443/c/" etc.
    static func normalizeBase(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let comps = URLComponents(string: s), let host = comps.host, !host.isEmpty else {
            return nil
        }
        let scheme = comps.scheme ?? "http"
        if let port = comps.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
