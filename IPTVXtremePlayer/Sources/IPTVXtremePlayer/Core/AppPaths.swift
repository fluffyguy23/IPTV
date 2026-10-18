import Foundation

/// Centralized on-disk locations under Application Support.
enum AppPaths {
    static let appFolderName = "IPTVXtremePlayer"

    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func subdirectory(_ name: String) -> URL {
        let dir = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var imageCache: URL { subdirectory("ImageCache") }
    static var dataCache: URL { subdirectory("DataCache") }
}
