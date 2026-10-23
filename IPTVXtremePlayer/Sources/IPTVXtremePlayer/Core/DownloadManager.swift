import Foundation

extension Notification.Name {
    /// Posted on the main thread whenever any download's status or progress changes.
    /// `userInfo["id"]` carries the record id; `userInfo["statusChanged"]` is true
    /// when the status (not just the byte count) changed.
    static let downloadsChanged = Notification.Name("downloadsChanged")
}

/// One offline download. Persisted in Downloads/index.json. Never stores the
/// stream URL (it embeds the account credentials) — only the MediaRef needed to
/// rebuild it from a connected session.
struct DownloadRecord: Codable, Equatable {
    enum Status: String, Codable { case queued, downloading, completed, failed }

    let id: String              // MediaRef.key ("movie:123", "episode:456")
    var ref: MediaRef
    var profileID: UUID         // profile the title belongs to (for resume + retry)
    var title: String
    var status: Status
    var bytesWritten: Int64 = 0
    var bytesExpected: Int64 = 0
    var fileName: String?       // inside Downloads/Files, set only once complete
    var errorMessage: String?
    var createdAt: Date = Date()
    var completedAt: Date?

    var progress: Double {
        guard bytesExpected > 0 else { return 0 }
        return min(1, Double(bytesWritten) / Double(bytesExpected))
    }
}

/// Downloads movies and episodes for offline playback into the app's own
/// Application Support folder, keeping a persistent index so they survive
/// restarts. Runs one download at a time (IPTV accounts often allow a single
/// connection). All state is touched on the main thread only.
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    enum EnqueueResult { case started, queued, alreadyDownloaded, alreadyInProgress, rejected(String) }

    private(set) var records: [DownloadRecord] = []

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60          // stall timeout between bytes
        config.timeoutIntervalForResource = 24 * 3600  // whole-file limit
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }()

    // In-memory only: remote URLs and resume data contain credentials.
    private var remoteURLs: [String: URL] = [:]
    private var resumeData: [String: Data] = [:]
    private var activeTask: URLSessionDownloadTask?
    private var activeID: String?
    private var cancelledByUser: Set<String> = []
    private var lastProgressPost: [String: TimeInterval] = [:]

    /// Minimum free space kept on disk after a download completes.
    private let reserveBytes: Int64 = 512 * 1024 * 1024

    // MARK: Paths

    static var root: URL { AppPaths.subdirectory("Downloads") }
    static var filesDir: URL {
        let dir = root.appendingPathComponent("Files", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Large media: keep it out of Time Machine.
            var url = dir
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return dir
    }
    private static var indexURL: URL { root.appendingPathComponent("index.json") }

    // MARK: Init / persistence

    private override init() {
        super.init()
        load()
        reconcileAfterLaunch()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.indexURL),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return }
        records = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.indexURL.path)
    }

    /// Anything left "in progress" by a previous run was interrupted; a "completed"
    /// record whose file vanished is dropped; stray files no record owns are removed.
    private func reconcileAfterLaunch() {
        var changed = false
        for i in records.indices {
            switch records[i].status {
            case .queued, .downloading:
                records[i].status = .failed
                records[i].errorMessage = "Interrupted — the app was closed during the download."
                records[i].bytesWritten = 0
                changed = true
            case .completed:
                if localFile(for: records[i]) == nil {
                    records[i].status = .failed
                    records[i].fileName = nil
                    records[i].errorMessage = "The downloaded file is missing."
                    changed = true
                }
            case .failed:
                break
            }
        }
        let owned = Set(records.compactMap { $0.status == .completed ? $0.fileName : nil })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.filesDir.path)) ?? []
        for f in files where !owned.contains(f) {
            try? FileManager.default.removeItem(at: Self.filesDir.appendingPathComponent(f))
        }
        if changed { persist() }
    }

    // MARK: Queries

    func record(for ref: MediaRef) -> DownloadRecord? { records.first { $0.id == ref.key } }
    func record(id: String) -> DownloadRecord? { records.first { $0.id == id } }

    private func localFile(for r: DownloadRecord) -> URL? {
        guard r.status == .completed, let name = r.fileName else { return nil }
        let url = Self.filesDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Local file for a fully downloaded title, or nil (never a partial download).
    func localFileURL(for ref: MediaRef) -> URL? { record(for: ref).flatMap(localFile(for:)) }

    var completedCount: Int { records.filter { $0.status == .completed }.count }

    var bytesOnDisk: Int64 {
        records.reduce(0) { sum, r in
            guard let url = localFile(for: r),
                  let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return sum }
            return sum + Int64(size)
        }
    }

    static func freeDiskBytes() -> Int64 {
        let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
    }

    // MARK: Commands

    /// Start (or queue) downloading a playable movie/episode.
    @discardableResult
    func enqueue(_ item: PlaybackItem, profileID: UUID) -> EnqueueResult {
        guard !item.isLive, item.ref.isResumable else {
            return .rejected("Live channels can't be downloaded.")
        }
        guard let scheme = item.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .rejected("This title is already stored on this Mac.")
        }
        let ext = item.url.pathExtension.lowercased()
        if ext == "m3u8" || ext == "m3u" {
            return .rejected("This title is streamed as HLS and can't be saved as a single file.")
        }
        if Self.freeDiskBytes() < reserveBytes * 2 {
            return .rejected("Not enough free disk space to start a download.")
        }

        let id = item.ref.key
        if let existing = record(id: id) {
            switch existing.status {
            case .completed where localFile(for: existing) != nil: return .alreadyDownloaded
            case .queued, .downloading: return .alreadyInProgress
            default: break      // failed / missing file → retry below
            }
        }

        var r = record(id: id) ?? DownloadRecord(id: id, ref: item.ref, profileID: profileID,
                                                  title: item.title, status: .queued)
        r.ref = item.ref
        r.profileID = profileID
        r.title = item.title
        r.status = .queued
        r.errorMessage = nil
        r.fileName = nil
        upsert(r)
        remoteURLs[id] = item.url
        post(id, statusChanged: true)

        if activeID == nil { startNext(); return .started }
        return .queued
    }

    /// Retry a failed download. Needs a connected session for the same profile,
    /// because stream URLs are rebuilt from credentials and never stored.
    @discardableResult
    func retry(id: String, session: Session?) -> EnqueueResult {
        guard let r = record(id: id) else { return .rejected("Download not found.") }
        if remoteURLs[id] == nil {
            guard let session = session else {
                return .rejected("Connect to your provider to retry this download.")
            }
            guard session.profile.id == r.profileID else {
                return .rejected("Connect to the profile this title was downloaded from to retry.")
            }
            guard let item = session.makeRemoteItem(from: r.ref) else { return .rejected("This title can no longer be found.") }
            return enqueue(item, profileID: r.profileID)
        }
        guard let url = remoteURLs[id] else { return .rejected("Download not found.") }
        let item = PlaybackItem(ref: r.ref, url: url, title: r.title, isLive: false, resumeSecs: 0, networkCaching: 3000)
        return enqueue(item, profileID: r.profileID)
    }

    /// Stop an active or queued download (it becomes "failed" and can be retried).
    func cancel(id: String) {
        guard var r = record(id: id), r.status == .queued || r.status == .downloading else { return }
        if activeID == id, let task = activeTask {
            cancelledByUser.insert(id)
            task.cancel { [weak self] data in
                DispatchQueue.main.async { if let data = data { self?.resumeData[id] = data } }
            }
        } else {
            r.status = .failed
            r.errorMessage = "Cancelled."
            upsert(r)
            post(id, statusChanged: true)
        }
    }

    /// Remove a download and its file to free space.
    func delete(id: String) {
        if activeID == id { cancelledByUser.insert(id); activeTask?.cancel() }
        if let r = record(id: id), let name = r.fileName {
            try? FileManager.default.removeItem(at: Self.filesDir.appendingPathComponent(name))
        }
        records.removeAll { $0.id == id }
        remoteURLs[id] = nil
        resumeData[id] = nil
        persist()
        post(id, statusChanged: true)
    }

    // MARK: Engine

    private func startNext() {
        guard activeID == nil,
              let next = records.first(where: { $0.status == .queued && remoteURLs[$0.id] != nil }) else { return }
        let id = next.id
        let task: URLSessionDownloadTask
        if let data = resumeData.removeValue(forKey: id) {
            task = urlSession.downloadTask(withResumeData: data)
        } else {
            var req = URLRequest(url: remoteURLs[id]!)
            req.setValue("IPTVXtremePlayer/1.1", forHTTPHeaderField: "User-Agent")
            task = urlSession.downloadTask(with: req)
        }
        task.taskDescription = id
        activeTask = task
        activeID = id
        update(id) { $0.status = .downloading; $0.errorMessage = nil }
        post(id, statusChanged: true)
        Log.info("Download started: \(id)")
        task.resume()
    }

    private func finish(_ id: String, failure: String?) {
        if let failure = failure {
            update(id) { $0.status = .failed; $0.errorMessage = failure }
            Log.warn("Download failed: \(id) — \(failure)")
        }
        if activeID == id { activeID = nil; activeTask = nil }
        post(id, statusChanged: true)
        startNext()
    }

    private func upsert(_ r: DownloadRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r } else { records.insert(r, at: 0) }
        persist()
    }

    private func update(_ id: String, persistNow: Bool = true, _ change: (inout DownloadRecord) -> Void) {
        guard let i = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[i])
        if persistNow { persist() }
    }

    private func post(_ id: String, statusChanged: Bool) {
        NotificationCenter.default.post(name: .downloadsChanged, object: self,
                                        userInfo: ["id": id, "statusChanged": statusChanged])
    }

    static func message(for error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "The network connection was lost."
            case NSURLErrorTimedOut: return "The server stopped responding."
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost: return "The server could not be reached."
            default: break
            }
        }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return "The disk is full." }
        return error.localizedDescription
    }
}

// MARK: - URLSessionDownloadDelegate (main queue)

extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        // Refuse downloads that would leave the disk (nearly) full.
        if totalBytesExpectedToWrite > 0,
           totalBytesExpectedToWrite - totalBytesWritten > Self.freeDiskBytes() - reserveBytes {
            cancelledByUser.insert(id)
            downloadTask.cancel()
            update(id) { $0.status = .failed; $0.errorMessage = "Not enough disk space for this download." }
            return
        }
        update(id, persistNow: false) {
            $0.bytesWritten = totalBytesWritten
            $0.bytesExpected = max(totalBytesExpectedToWrite, 0)
        }
        let now = Date().timeIntervalSince1970
        if now - (lastProgressPost[id] ?? 0) >= 0.25 {
            lastProgressPost[id] = now
            post(id, statusChanged: false)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription, let r = record(id: id) else { return }

        // Validate before accepting: a 2xx video response, not an error page.
        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        let mime = (http?.mimeType ?? "").lowercased()
        let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var failure: String?
        if !(200...299).contains(status) {
            failure = status == 401 || status == 403
                ? "The provider refused the download (HTTP \(status)). Your plan may not allow another connection."
                : "The video is unavailable (HTTP \(status))."
        } else if mime.hasPrefix("text/") || mime.contains("json") || mime.contains("html") {
            failure = "The server returned an error page instead of a video."
        } else if size < 64 * 1024 {
            failure = "The downloaded file is too small to be a video."
        } else if r.bytesExpected > 0 && size < r.bytesExpected {
            failure = "The download was incomplete."
        }

        if failure == nil {
            let ext = [r.ref.containerExt, downloadTask.originalRequest?.url?.pathExtension, "mp4"]
                .compactMap { $0?.lowercased() }.first { !$0.isEmpty && $0.count <= 5 } ?? "mp4"
            let safeID = id.replacingOccurrences(of: #"[^A-Za-z0-9_-]"#, with: "-", options: .regularExpression)
            let name = "\(safeID).\(ext)"
            let dest = Self.filesDir.appendingPathComponent(name)
            do {
                try? FileManager.default.removeItem(at: dest)
                // Move (same volume) so the file only appears once it is complete.
                try FileManager.default.moveItem(at: location, to: dest)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dest.path)
                update(id) {
                    $0.status = .completed
                    $0.fileName = name
                    $0.bytesWritten = size
                    $0.bytesExpected = size
                    $0.completedAt = Date()
                    $0.errorMessage = nil
                }
                remoteURLs[id] = nil
                resumeData[id] = nil
                Log.info("Download complete: \(id) (\(size) bytes)")
            } catch {
                failure = "Couldn't save the file: \(Self.message(for: error))"
            }
        }
        if let failure = failure {
            update(id) { $0.status = .failed; $0.errorMessage = failure; $0.bytesWritten = 0 }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription else { return }
        let userCancelled = cancelledByUser.remove(id) != nil
        if let error = error {
            if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                resumeData[id] = data      // lets Retry continue where it stopped
            }
            if record(id: id) == nil { finish(id, failure: nil); return }   // deleted meanwhile
            let current = record(id: id)
            let message = userCancelled
                ? (current?.status == .failed ? current?.errorMessage ?? "Cancelled." : "Cancelled.")
                : Self.message(for: error)
            finish(id, failure: message)
        } else {
            finish(id, failure: nil)   // success/validation already recorded
        }
    }
}
