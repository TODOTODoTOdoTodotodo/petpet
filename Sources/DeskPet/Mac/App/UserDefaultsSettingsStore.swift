import Foundation

/// This object is responsible for keeping DeskPet settings in macOS `UserDefaults`,
/// under the same keys earlier versions used, so saved choices carry over.
final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    /// 예전에 정수로 저장한 값(petCount)도 숫자로 읽음
    func number(forKey key: String) -> Double? { (defaults.object(forKey: key) as? NSNumber)?.doubleValue }
    func flag(forKey key: String) -> Bool? { defaults.object(forKey: key) as? Bool }
    func strings(forKey key: String) -> [String]? { defaults.stringArray(forKey: key) }

    func set(string value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    func set(number value: Double?, forKey key: String) { defaults.set(value, forKey: key) }
    func set(flag value: Bool?, forKey key: String) { defaults.set(value, forKey: key) }
    func set(strings value: [String]?, forKey key: String) { defaults.set(value, forKey: key) }
}
