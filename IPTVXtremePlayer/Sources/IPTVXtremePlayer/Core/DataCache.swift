import Foundation
import CryptoKit

/// Generic on-disk JSON cache for API responses, with optional TTL.
/// Keyed per profile so switching accounts never mixes content.
final class DataCache {
    private let folder: URL

    init(namespace: String) {
        folder = AppPaths.dataCache.appendingPathComponent(namespace, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private struct Envelope<T: Codable>: Codable {
        let storedAt: Date
        let value: T
    }

    private func fileURL(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return folder.appendingPathComponent(hash + ".json")
    }

    func save<T: Codable>(_ value: T, key: String) {
        let env = Envelope(storedAt: Date(), value: value)
        if let data = try? JSONEncoder().encode(env) {
            try? data.write(to: fileURL(key), options: .atomic)
        }
    }

    /// Return cached value if present and (if maxAge given) still fresh.
    func load<T: Codable>(_ type: T.Type, key: String, maxAge: TimeInterval? = nil) -> T? {
        guard let data = try? Data(contentsOf: fileURL(key)),
              let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) else {
            return nil
        }
        if let maxAge = maxAge, Date().timeIntervalSince(env.storedAt) > maxAge {
            return nil
        }
        return env.value
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
