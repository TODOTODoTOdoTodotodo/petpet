import Foundation

/// This object is responsible for writing timestamped debug lines to
/// `~/Library/Logs/DeskPet/pet_debug.log` off the main thread.
final class PetLogger {
    static let shared = PetLogger()

    let fileURL: URL
    private let queue = DispatchQueue(label: "DeskPet.PetLogger")
    private let handle: FileHandle?
    private let formatter: DateFormatter

    private init() {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DeskPet")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("pet_debug.log")
        // 실행마다 새로 기록
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func log(_ message: String) {
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        queue.async { [handle] in
            FileHandle.standardOutput.write(Data(line.utf8))
            handle?.write(Data(line.utf8))
        }
    }
}
