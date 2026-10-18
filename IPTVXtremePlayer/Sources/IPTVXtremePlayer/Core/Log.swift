import Foundation
import os

/// Lightweight logging. Credentials are never passed to these helpers; the
/// networking layer redacts usernames/passwords from any URL before logging.
enum Log {
    private static let logger = Logger(subsystem: "com.iptvxtreme.player", category: "app")

    static func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    static func warn(_ message: String) { logger.warning("\(message, privacy: .public)") }
    static func error(_ message: String) { logger.error("\(message, privacy: .public)") }

    /// Redact username/password query params and Xtream path credentials.
    static func redact(_ urlString: String) -> String {
        var s = urlString
        // Query-style credentials
        s = s.replacingOccurrences(of: #"(?i)(username=)[^&]+"#, with: "$1***", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)(password=)[^&]+"#, with: "$1***", options: .regularExpression)
        // Path-style: /live/USER/PASS/..  /movie/USER/PASS/..  /series/USER/PASS/..
        s = s.replacingOccurrences(of: #"(/(?:live|movie|series)/)[^/]+/[^/]+/"#,
                                    with: "$1***/***/", options: .regularExpression)
        return s
    }
}
