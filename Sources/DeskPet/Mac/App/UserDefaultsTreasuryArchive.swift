import Foundation

/// This object is responsible for keeping the collection bytes in macOS `UserDefaults` (`treasury.v1`),
/// moving an unreadable copy to `treasury.broken` instead of deleting it.
final class UserDefaultsTreasuryArchive: TreasuryArchive {
    private let defaults: UserDefaults
    static let key = "treasury.v1"
    static let brokenKey = "treasury.broken"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadData() -> Data? { defaults.data(forKey: Self.key) }

    func save(_ data: Data) { defaults.set(data, forKey: Self.key) }

    func setAside(_ data: Data) {
        defaults.set(data, forKey: Self.brokenKey)
        defaults.removeObject(forKey: Self.key)
    }
}
