import Foundation

/// This object is responsible for where DeskPet keeps its files on Windows:
/// settings and collection in `%APPDATA%\DeskPet`, the log in `%LOCALAPPDATA%\DeskPet\Logs`.
/// `DESKPET_DATA_DIR` moves everything into one folder (tests, CI).
enum WindowsPaths {
    private static var environment: [String: String] { ProcessInfo.processInfo.environment }

    static var data: URL {
        if let override = environment["DESKPET_DATA_DIR"] { return URL(fileURLWithPath: override, isDirectory: true) }
        let base = environment["APPDATA"] ?? FileManager.default.temporaryDirectory.path
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("DeskPet", isDirectory: true)
    }

    static var logs: URL {
        if let override = environment["DESKPET_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent("Logs", isDirectory: true)
        }
        let base = environment["LOCALAPPDATA"] ?? FileManager.default.temporaryDirectory.path
        return URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent("DeskPet/Logs", isDirectory: true)
    }

    static var settingsFile: URL { data.appendingPathComponent("settings.json") }
}

/// This object is responsible for writing DeskPet's behavior log on Windows, started fresh at each launch.
final class WindowsLogger {
    static let shared = WindowsLogger()

    let fileURL: URL
    private let handle: FileHandle?
    private let formatter: DateFormatter

    private init() {
        let folder = WindowsPaths.logs
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("pet_debug.log")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        handle?.write(Data(line.utf8))
    }
}

/// This object is responsible for keeping the collection bytes in `treasury.json` next to the settings,
/// moving an unreadable copy to `treasury.broken.json` instead of deleting it.
final class FileTreasuryArchive: TreasuryArchive {
    private let folder: URL

    init(folder: URL = WindowsPaths.data) {
        self.folder = folder
    }

    private var file: URL { folder.appendingPathComponent("treasury.json") }

    func loadData() -> Data? { try? Data(contentsOf: file) }

    func save(_ data: Data) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    func setAside(_ data: Data) {
        try? data.write(to: folder.appendingPathComponent("treasury.broken.json"), options: .atomic)
        try? FileManager.default.removeItem(at: file)
    }
}
