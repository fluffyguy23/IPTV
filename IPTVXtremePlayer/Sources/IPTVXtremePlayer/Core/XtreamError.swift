import Foundation

enum XtreamError: LocalizedError {
    case invalidURL
    case network(String)
    case timeout
    case httpStatus(Int)
    case authFailed              // server reachable but credentials rejected
    case subscriptionExpired
    case subscriptionBanned
    case malformedResponse
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server address is not valid."
        case .network(let m): return "Network error: \(m)"
        case .timeout: return "The server did not respond in time."
        case .httpStatus(let c): return "The server returned an error (HTTP \(c))."
        case .authFailed: return "Incorrect username or password."
        case .subscriptionExpired: return "This subscription has expired."
        case .subscriptionBanned: return "This account is banned or disabled."
        case .malformedResponse: return "The server sent an unexpected response."
        case .empty: return "The server returned no data."
        }
    }
}
