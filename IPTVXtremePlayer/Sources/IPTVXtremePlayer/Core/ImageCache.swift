import AppKit
import CryptoKit

/// Two-tier (memory + disk) image loader for posters and channel logos.
/// De-duplicates concurrent requests for the same URL.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        memory.countLimit = 400
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    private func diskURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return AppPaths.imageCache.appendingPathComponent(hash)
    }

    func image(for urlString: String?) async -> NSImage? {
        guard let urlString = urlString, !urlString.isEmpty,
              let url = URL(string: urlString) else { return nil }

        if let cached = memory.object(forKey: urlString as NSString) { return cached }

        if let existing = inFlight[urlString] { return await existing.value }

        let task = Task<NSImage?, Never> { [weak self] in
            guard let self = self else { return nil }
            // Disk hit?
            let disk = await self.diskURL(for: urlString)
            if let data = try? Data(contentsOf: disk), let img = NSImage(data: data) {
                await self.store(img, data: data, key: urlString, disk: nil)
                return img
            }
            // Network
            guard let (data, _) = try? await self.session.data(from: url),
                  let img = NSImage(data: data) else { return nil }
            await self.store(img, data: data, key: urlString, disk: disk)
            return img
        }
        inFlight[urlString] = task
        let result = await task.value
        inFlight[urlString] = nil
        return result
    }

    private func store(_ img: NSImage, data: Data, key: String, disk: URL?) {
        memory.setObject(img, forKey: key as NSString)
        if let disk = disk { try? data.write(to: disk, options: .atomic) }
    }

    func clearDisk() {
        try? FileManager.default.removeItem(at: AppPaths.imageCache)
        memory.removeAllObjects()
    }
}
