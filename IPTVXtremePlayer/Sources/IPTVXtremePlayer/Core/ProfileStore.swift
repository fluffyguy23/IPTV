import Foundation

/// Persists the list of profiles (metadata in UserDefaults; passwords in Keychain)
/// and tracks which profile is currently selected.
final class ProfileStore {
    static let shared = ProfileStore()

    private let defaults = UserDefaults.standard
    private let profilesKey = "profiles.v1"
    private let lastUsedKey = "profiles.lastUsed"

    private(set) var profiles: [Profile] = []

    private init() {
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: profilesKey)
        }
    }

    // MARK: CRUD

    /// Create or update a profile, storing the password in the Keychain.
    func save(_ profile: Profile, password: String?) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        if let password = password, !password.isEmpty {
            CredentialStore.set(password, for: profile.id)
        }
        persist()
    }

    func delete(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        CredentialStore.delete(for: profile.id)
        if lastUsedID == profile.id { lastUsedID = nil }
        persist()
    }

    func password(for profile: Profile) -> String? {
        CredentialStore.password(for: profile.id)
    }

    // MARK: Last used

    var lastUsedID: UUID? {
        get {
            guard let s = defaults.string(forKey: lastUsedKey) else { return nil }
            return UUID(uuidString: s)
        }
        set {
            if let id = newValue { defaults.set(id.uuidString, forKey: lastUsedKey) }
            else { defaults.removeObject(forKey: lastUsedKey) }
        }
    }

    var lastUsedProfile: Profile? {
        guard let id = lastUsedID else { return nil }
        return profiles.first { $0.id == id }
    }
}
