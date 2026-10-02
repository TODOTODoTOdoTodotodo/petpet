import AppKit

public class AppController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlayController: OverlayController!
    private var petController: PetController!
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background accessory app (No Dock icon, pure Menu Bar app)
        NSApp.setActivationPolicy(.accessory)
        
        // Prevent App Nap from freezing the background animation loop
        _ = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Continuous DeskPet Animation and Interaction"
        )
        
        // Setup Overlay
        overlayController = OverlayController()
        overlayController.show()
        
        // Find Skins directory
        let fm = FileManager.default
        let currentDir = URL(fileURLWithPath: fm.currentDirectoryPath)
        var candidates = [
            currentDir.appendingPathComponent("Assets/Skins"),
            Bundle.main.bundleURL.appendingPathComponent("Assets/Skins"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Assets/Skins"),
            currentDir.appendingPathComponent("../Assets/Skins")
        ]
        if let resURL = Bundle.main.resourceURL {
            candidates.insert(resURL.appendingPathComponent("Assets/Skins"), at: 0)
        }
        
        let skinsDir = candidates.first { fm.fileExists(atPath: $0.path) } ?? currentDir.appendingPathComponent("Assets/Skins")
        print("[AppController] Resolved skins directory: \(skinsDir.path)")
        
        // Setup Pet Controller
        petController = PetController(overlayController: overlayController, skinsDirectory: skinsDir)
        
        // Setup Menu Bar
        setupStatusMenu()
    }
    
    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "👾"
            button.toolTip = "DeskPet - Desktop Screenmate"
        }
        
        rebuildMenu()
    }
    
    public func rebuildMenu() {
        let menu = NSMenu()
        
        // Title
        let titleItem = NSMenuItem(title: "🐾 DeskPet Companion", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Character Switcher Submenu
        let skinMenu = NSMenu()
        for skinName in petController.availableSkins.keys.sorted() {
            let item = NSMenuItem(title: skinName, action: #selector(didSelectSkin(_:)), keyEquivalent: "")
            item.target = self
            item.state = (skinName == petController.currentSkinName) ? .on : .off
            skinMenu.addItem(item)
        }
        let skinSubmenuItem = NSMenuItem(title: "Character Skin", action: nil, keyEquivalent: "")
        skinSubmenuItem.submenu = skinMenu
        menu.addItem(skinSubmenuItem)
        
        // Add / Remove Pet
        let addPetItem = NSMenuItem(title: "Add Another Pet (+)", action: #selector(didTapAddPet), keyEquivalent: "a")
        addPetItem.target = self
        menu.addItem(addPetItem)
        
        let removePetItem = NSMenuItem(title: "Remove Pet (-)", action: #selector(didTapRemovePet), keyEquivalent: "r")
        removePetItem.target = self
        menu.addItem(removePetItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Size / Scale Submenu
        let sizeMenu = NSMenu()
        let sizes: [(String, CGFloat)] = [("Small (1.0x)", 1.0), ("Medium (1.5x)", 1.5), ("Large (2.0x)", 2.0)]
        for (label, scale) in sizes {
            let item = NSMenuItem(title: label, action: #selector(didSelectScale(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = scale
            sizeMenu.addItem(item)
        }
        let sizeSubmenuItem = NSMenuItem(title: "Pet Size", action: nil, keyEquivalent: "")
        sizeSubmenuItem.submenu = sizeMenu
        menu.addItem(sizeSubmenuItem)
        
        // Opacity Submenu
        let opacityMenu = NSMenu()
        let opacities: [(String, CGFloat)] = [("100% (Solid)", 1.0), ("75% (Subtle)", 0.75), ("50% (Ghost)", 0.5)]
        for (label, alpha) in opacities {
            let item = NSMenuItem(title: label, action: #selector(didSelectOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = alpha
            opacityMenu.addItem(item)
        }
        let opacitySubmenuItem = NSMenuItem(title: "Ghost Opacity", action: nil, keyEquivalent: "")
        opacitySubmenuItem.submenu = opacityMenu
        menu.addItem(opacitySubmenuItem)
        
        // Logs
        let logItem = NSMenuItem(title: "Open Debug Log (pet_debug.log)", action: #selector(didTapOpenLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit DeskPet", action: #selector(didTapQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc private func didSelectSkin(_ sender: NSMenuItem) {
        petController.switchSkin(to: sender.title)
        rebuildMenu()
    }
    
    @objc private func didTapAddPet() {
        petController.addPet()
    }
    
    @objc private func didTapRemovePet() {
        petController.removePet()
    }
    
    @objc private func didSelectScale(_ sender: NSMenuItem) {
        if let scale = sender.representedObject as? CGFloat {
            petController.setPetScale(scale)
        }
    }
    
    @objc private func didSelectOpacity(_ sender: NSMenuItem) {
        if let alpha = sender.representedObject as? CGFloat {
            overlayController.setOpacity(alpha)
        }
    }
    
    @objc private func didTapOpenLog() {
        let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let logURL = currentDir.appendingPathComponent("pet_debug.log")
        NSWorkspace.shared.open(logURL)
    }
    
    @objc private func didTapQuit() {
        NSApp.terminate(nil)
    }
}
