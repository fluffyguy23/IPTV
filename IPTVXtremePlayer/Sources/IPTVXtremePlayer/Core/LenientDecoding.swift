import Foundation

/// Xtream Codes servers are wildly inconsistent: the same field may be an Int,
/// a quoted String, a Double, or absent. These helpers decode leniently so one
/// malformed field never fails the whole response.
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let v = try? decodeIfPresent(String.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return String(v) }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? "1" : "0" }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v ? 1 : 0 }
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return Int(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if let v = Int(trimmed) { return v }
            if let d = Double(trimmed) { return Int(d) }
        }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return Double(v) }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let v = try? decodeIfPresent(Bool.self, forKey: key) { return v }
        if let v = try? decodeIfPresent(Int.self, forKey: key) { return v != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) {
            switch s.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no", "": return false
            default: return nil
            }
        }
        return nil
    }

    /// Some endpoints return `[]` when there is no data and an object otherwise.
    /// Returns nil for the empty-array / wrong-shape case instead of throwing.
    func lenientStringArray(_ key: Key) -> [String]? {
        if let v = try? decodeIfPresent([String].self, forKey: key) { return v }
        if let s = lenientString(key), !s.isEmpty { return [s] }
        return nil
    }
}
