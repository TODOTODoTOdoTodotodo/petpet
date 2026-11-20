import Foundation

/// This object is responsible for keeping named setting values between launches, without knowing what they mean.
/// `nil` from a read means "never saved", so the caller's default applies. Writing `nil` forgets the value.
protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func number(forKey key: String) -> Double?
    func flag(forKey key: String) -> Bool?
    func strings(forKey key: String) -> [String]?
    func set(string value: String?, forKey key: String)
    func set(number value: Double?, forKey key: String)
    func set(flag value: Bool?, forKey key: String)
    func set(strings value: [String]?, forKey key: String)
}

/// This object is responsible for a settings store kept as one small JSON file
/// (Windows `%APPDATA%\DeskPet\settings.json`). Every write saves the whole file atomically;
/// a missing or broken file reads as empty, so the app starts with defaults instead of failing.
final class JSONFileSettingsStore: SettingsStore {
    /// 값 하나 (JSON의 문자열·숫자·참거짓·문자열 배열)
    private enum Value: Codable, Equatable {
        case string(String)
        case number(Double)
        case flag(Bool)
        case strings([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            // 참거짓을 먼저 봄 (JSON의 true가 숫자로 읽히지 않게)
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else if let number = try? container.decode(Double.self) {
                self = .number(number)
            } else if let string = try? container.decode(String.self) {
                self = .string(string)
            } else {
                self = .strings(try container.decode([String].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .flag(let value): try container.encode(value)
            case .strings(let value): try container.encode(value)
            }
        }
    }

    let fileURL: URL
    private var values: [String: Value]

    init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        values = data.flatMap { try? JSONDecoder().decode([String: Value].self, from: $0) } ?? [:]
    }

    func string(forKey key: String) -> String? {
        if case .string(let value)? = values[key] { return value }
        return nil
    }

    func number(forKey key: String) -> Double? {
        if case .number(let value)? = values[key] { return value }
        return nil
    }

    func flag(forKey key: String) -> Bool? {
        if case .flag(let value)? = values[key] { return value }
        return nil
    }

    func strings(forKey key: String) -> [String]? {
        if case .strings(let value)? = values[key] { return value }
        return nil
    }

    func set(string value: String?, forKey key: String) { put(value.map(Value.string), key) }
    func set(number value: Double?, forKey key: String) { put(value.map(Value.number), key) }
    func set(flag value: Bool?, forKey key: String) { put(value.map(Value.flag), key) }
    func set(strings value: [String]?, forKey key: String) { put(value.map(Value.strings), key) }

    private func put(_ value: Value?, _ key: String) {
        guard values[key] != value else { return }
        values[key] = value
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(values) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
