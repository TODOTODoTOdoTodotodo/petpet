import Foundation
import CoreGraphics

public class PetLogger {
    public static let shared = PetLogger()
    
    private let logFileURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    
    private init() {
        let projectPath = "/Users/HH191_1/Documents/private"
        let projectURL = URL(fileURLWithPath: projectPath)
        self.logFileURL = projectURL.appendingPathComponent("pet_debug.log")
        
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
        
        // Create or clear log file
        try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
        self.fileHandle = try? FileHandle(forWritingTo: logFileURL)
        
        log("🚀 [PetLogger Initialized] Output: \(logFileURL.path)")
    }
    
    public func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let fullLine = "[\(timestamp)] \(message)\n"
        
        print(fullLine, terminator: "")
        
        if let data = fullLine.data(using: .utf8) {
            fileHandle?.seekToEndOfFile()
            fileHandle?.write(data)
        }
    }
    
    public func logStateChange(petId: String, from: String, to: String, position: CGPoint, screen: String) {
        let xStr = String(format: "%.1f", position.x)
        let yStr = String(format: "%.1f", position.y)
        log("🐾 [\(petId)] STATE: [\(from)] ➔ [\(to)] at (\(xStr), \(yStr)) on Screen: [\(screen)]")
    }
    
    public func logInteraction(petId: String, action: String, details: String, position: CGPoint) {
        let xStr = String(format: "%.1f", position.x)
        let yStr = String(format: "%.1f", position.y)
        log("⚡️ [\(petId)] INTERACTION: [\(action)] - \(details) at (\(xStr), \(yStr))")
    }
    
    public func logScreenTransit(petId: String, from: String, to: String, newPos: CGPoint) {
        let xStr = String(format: "%.1f", newPos.x)
        let yStr = String(format: "%.1f", newPos.y)
        log("🌐 [\(petId)] SCREEN WARP: [\(from)] ➔ [\(to)] new pos: (\(xStr), \(yStr))")
    }
}
