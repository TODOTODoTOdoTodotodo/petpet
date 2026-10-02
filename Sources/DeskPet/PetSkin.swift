import AppKit
import SpriteKit

public enum Direction: String {
    case south
    case east
    case west
    case north
}

public class PetSkin {
    public let id: String
    public let name: String
    public let size: CGSize
    public let basePath: URL
    
    // Direction -> Idle texture
    public var idleTextures: [Direction: SKTexture] = [:]
    
    // Direction -> Walking textures (array of frames)
    public var walkTextures: [Direction: [SKTexture]] = [:]
    
    // Action / Special textures
    public var actionTextures: [Direction: [SKTexture]] = [:]
    
    public init(name: String, directory: URL) {
        self.id = directory.lastPathComponent
        self.name = name
        self.basePath = directory
        self.size = CGSize(width: 48, height: 48)
        loadFromDirectory()
    }
    
    private func loadTexture(relativePath: String) -> SKTexture? {
        let fileURL = basePath.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let nsImage = NSImage(contentsOf: fileURL) else {
            return nil
        }
        let texture = SKTexture(image: nsImage)
        texture.filteringMode = .nearest // Preserve pixel-art crispness
        return texture
    }
    
    private func loadFromDirectory() {
        let metaURL = basePath.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = json["states"] as? [[String: Any]],
              let firstState = states.first else {
            fallbackLoad()
            return
        }
        
        let frames = firstState["frames"] as? [String: Any] ?? [:]
        
        // 1. Idle / Rotations
        if let rotations = frames["rotations"] as? [String: String] {
            for (dirKey, path) in rotations {
                if let dir = Direction(rawValue: dirKey), let texture = loadTexture(relativePath: path) {
                    idleTextures[dir] = texture
                }
            }
        }
        
        // Check for separate idle state if available (like in Radish)
        if states.count > 1 {
            for state in states.dropFirst() {
                if let stateFrames = state["frames"] as? [String: Any],
                   let rot = stateFrames["rotations"] as? [String: String] {
                    for (dirKey, path) in rot {
                        if let dir = Direction(rawValue: dirKey), let texture = loadTexture(relativePath: path) {
                            idleTextures[dir] = texture
                        }
                    }
                }
            }
        }
        
        // 2. Animations (Walking or Running)
        if let animations = frames["animations"] as? [String: Any] {
            // Find walking or running animation key
            let walkKey = animations.keys.first { $0.contains("Walk") || $0.contains("Run") }
            if let walkKey = walkKey, let walkDict = animations[walkKey] as? [String: Any] {
                for (dirKey, frameList) in walkDict {
                    let dir: Direction?
                    if dirKey.hasPrefix("south") { dir = .south }
                    else if dirKey.hasPrefix("north") { dir = .north }
                    else if dirKey.hasPrefix("east") { dir = .east }
                    else if dirKey.hasPrefix("west") { dir = .west }
                    else { dir = nil }
                    
                    guard let resolvedDir = dir, walkTextures[resolvedDir] == nil else { continue }
                    
                    if let paths = frameList as? [String] {
                        let textures = paths.compactMap { loadTexture(relativePath: $0) }
                        if !textures.isEmpty {
                            walkTextures[resolvedDir] = textures
                        }
                    }
                }
            }
            
            // 3. Action animation (Attack, etc.)
            let actionKey = animations.keys.first { $0.contains("attack") || $0.contains("swing") }
            if let actionKey = actionKey, let actionDict = animations[actionKey] as? [String: Any] {
                for (dirKey, frameList) in actionDict {
                    guard let dir = Direction(rawValue: dirKey),
                          let paths = frameList as? [String] else { continue }
                    let textures = paths.compactMap { loadTexture(relativePath: $0) }
                    if !textures.isEmpty {
                        actionTextures[dir] = textures
                    }
                }
            }
        }
        
        // Fill missing west walking frames by mirroring east if needed
        if walkTextures[.west] == nil, let eastFrames = walkTextures[.east] {
            walkTextures[.west] = eastFrames
        }
        if idleTextures[.west] == nil, let eastIdle = idleTextures[.east] {
            idleTextures[.west] = eastIdle
        }
        if actionTextures[.west] == nil, let eastAction = actionTextures[.east] {
            actionTextures[.west] = eastAction
        }
    }
    
    private func fallbackLoad() {
        print("[PetSkin] Fallback loading for \(name)")
    }
}
