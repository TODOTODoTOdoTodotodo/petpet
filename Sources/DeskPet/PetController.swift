import AppKit
import SpriteKit

public class PetController: WindowObserverDelegate {
    public private(set) var availableSkins: [String: PetSkin] = [:]
    public private(set) var currentSkinName: String = "Goblin"
    
    private let overlayController: OverlayController
    private let windowObserver: WindowObserver
    
    public init(overlayController: OverlayController, skinsDirectory: URL) {
        self.overlayController = overlayController
        self.windowObserver = WindowObserver()
        self.windowObserver.delegate = self
        
        loadSkins(from: skinsDirectory)
        
        // Spawn default pet on primary overlay
        if let defaultSkin = availableSkins["Goblin"] ?? availableSkins.values.first,
           let primaryOverlay = overlayController.overlays.first {
            currentSkinName = defaultSkin.name
            _ = primaryOverlay.scene.addPet(skin: defaultSkin, id: "Goblin-1")
        }
        
        // Start window detection
        self.windowObserver.start(interval: 0.3)
    }
    
    public func loadSkins(from directory: URL) {
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return
        }
        
        for dir in subdirs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
                let skinName = dir.lastPathComponent
                let skin = PetSkin(name: skinName, directory: dir)
                availableSkins[skinName] = skin
                PetLogger.shared.log("📦 Loaded skin asset: \(skinName)")
            }
        }
    }
    
    public func switchSkin(to skinName: String) {
        guard let newSkin = availableSkins[skinName] else { return }
        currentSkinName = skinName
        for overlay in overlayController.overlays {
            for pet in overlay.scene.pets {
                pet.skin = newSkin
            }
        }
        PetLogger.shared.log("🔄 Switched all pets to skin: \(skinName)")
    }
    
    public func addPet(skinName: String? = nil) {
        let targetName = skinName ?? currentSkinName
        guard let skin = availableSkins[targetName] ?? availableSkins.values.first,
              let overlay = overlayController.overlays.first else { return }
        _ = overlay.scene.addPet(skin: skin)
    }
    
    public func removePet() {
        for overlay in overlayController.overlays {
            if !overlay.scene.pets.isEmpty {
                overlay.scene.removePet(at: overlay.scene.pets.count - 1)
                return
            }
        }
    }
    
    public func setPetScale(_ scale: CGFloat) {
        for overlay in overlayController.overlays {
            for pet in overlay.scene.pets {
                pet.scaleMultiplier = scale
            }
        }
    }
    
    // MARK: - WindowObserverDelegate
    public func windowObserver(_ observer: WindowObserver, didUpdateWindowsByScreen windowsByScreen: [CGDirectDisplayID: [CGRect]]) {
        for overlay in overlayController.overlays {
            guard let screenID = overlay.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if let rects = windowsByScreen[screenID] {
                overlay.scene.updateWindows(rects)
            }
        }
    }
}
