import Foundation

extension UserDefaults {
    /// Stores `value` as JSON. A value that fails to encode leaves the key untouched.
    func store<Value: Encodable>(_ value: Value, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        set(data, forKey: key)
    }

    /// - Returns: nil when the key is absent or its JSON no longer decodes as `type`.
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
