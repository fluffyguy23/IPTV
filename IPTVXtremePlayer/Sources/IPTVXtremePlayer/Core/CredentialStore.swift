import Foundation
import CryptoKit
import IOKit

/// Credential persistence that survives app updates WITHOUT a re-login prompt.
///
/// Background: self-distributed builds are ad-hoc signed, so each build has a
/// different code signature. The macOS Keychain ties item access to that
/// signature, so after replacing the app a fresh build can be re-prompted (or
/// denied) for Keychain items — which looks like "I have to log in again".
///
/// To avoid that, credentials are stored primarily in an encrypted file under
/// Application Support (outside the replaceable app bundle). The file is sealed
/// with AES-GCM using a key derived from this Mac's hardware UUID, so it is
/// readable only on this machine. The Keychain is still written as a secondary
/// copy. Reads try the file first → zero prompts across updates.
enum CredentialStore {
    static func set(_ password: String, for id: UUID) {
        FileCredentials.set(password, for: id.uuidString)
        KeychainService.setPassword(password, for: id)   // secondary copy
    }

    static func password(for id: UUID) -> String? {
        if let fromFile = FileCredentials.get(for: id.uuidString) {
            return fromFile
        }
        // Legacy Keychain-only credential: migrate it into the encrypted file so
        // the next read (and every future update) hits the file and never re-prompts.
        guard let fromKeychain = KeychainService.password(for: id) else { return nil }
        FileCredentials.set(fromKeychain, for: id.uuidString)
        return fromKeychain
    }

    static func delete(for id: UUID) {
        FileCredentials.delete(for: id.uuidString)
        KeychainService.deletePassword(for: id)
    }
}

/// Encrypted, machine-bound credential file. Internal to CredentialStore.
private enum FileCredentials {
    private static var fileURL: URL { AppPaths.support.appendingPathComponent(".credentials") }

    private static let key: SymmetricKey = {
        let uuid = machineUUID()
        let seed = "IPTVXtremePlayer.v1." + (uuid.isEmpty ? "static-fallback-seed" : uuid)
        return SymmetricKey(data: Data(SHA256.hash(data: Data(seed.utf8))))
    }()

    static func set(_ password: String, for account: String) {
        var dict = load()
        dict[account] = password
        save(dict)
    }
    static func get(for account: String) -> String? { load()[account] }
    static func delete(for account: String) {
        var dict = load()
        dict[account] = nil
        save(dict)
    }

    private static func load() -> [String: String] {
        guard let sealed = try? Data(contentsOf: fileURL),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: plain) else {
            return [:]
        }
        return dict
    }

    private static func save(_ dict: [String: String]) {
        guard let json = try? JSONEncoder().encode(dict),
              let sealed = try? AES.GCM.seal(json, using: key).combined else { return }
        try? sealed.write(to: fileURL, options: .atomic)
        // Restrict to the current user.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// This Mac's hardware UUID (ties the encrypted file to this machine).
    private static func machineUUID() -> String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "" }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0) else {
            return ""
        }
        return (cf.takeRetainedValue() as? String) ?? ""
    }
}
