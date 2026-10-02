import AppKit
import SpriteKit

public class ScreenOverlay {
    public let screen: NSScreen
    public let panel: NSPanel
    public let skView: SKView
    public let scene: PetScene
    public let screenName: String
    
    public init(screen: NSScreen, index: Int) {
        self.screen = screen
        self.screenName = screen.localizedName.isEmpty ? "Display \(index + 1)" : screen.localizedName
        
        let frame = screen.frame
        self.panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.panel.level = .statusBar
        self.panel.isFloatingPanel = true
        self.panel.backgroundColor = .clear
        self.panel.isOpaque = false
        self.panel.hasShadow = false
        self.panel.hidesOnDeactivate = false
        self.panel.canHide = false
        self.panel.isMovable = false
        self.panel.ignoresMouseEvents = true // Pass-through by default
        self.panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        
        // SpriteKit view
        let localSize = frame.size
        self.skView = SKView(frame: CGRect(origin: .zero, size: localSize))
        self.skView.allowsTransparency = true
        self.skView.wantsLayer = true
        self.skView.layer?.backgroundColor = .clear
        self.skView.isPaused = false
        self.skView.preferredFramesPerSecond = 60
        
        self.scene = PetScene(size: localSize)
        self.scene.screenName = screenName
        self.scene.scaleMode = .resizeFill
        self.skView.presentScene(scene)
        
        self.panel.contentView = skView
        self.panel.setFrame(frame, display: true)
        self.panel.orderFrontRegardless()
        
        PetLogger.shared.log("🖥️ [ScreenOverlay Ready] \(screenName): \(Int(frame.width))x\(Int(frame.height)) at origin: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
    }
    
    public func setOpacity(_ alpha: CGFloat) {
        panel.alphaValue = alpha
    }
}

public class OverlayController {
    public private(set) var overlays: [ScreenOverlay] = []
    private var hitTestTimer: Timer?
    private var isAnyPetDragging: Bool = false
    
    private var localEventMonitor: Any?
    private var draggedPetInfo: (pet: PetNode, sourceOverlay: ScreenOverlay, dragOffsetGlobal: CGPoint)?
    
    public init() {
        setupOverlays()
        startSmartHitTesting()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            return self?.handleGlobalMouse(event) ?? event
        }
    }
    
    public func setupOverlays() {
        for overlay in overlays {
            overlay.panel.orderOut(nil)
        }
        overlays.removeAll()
        
        for (idx, screen) in NSScreen.screens.enumerated() {
            let overlay = ScreenOverlay(screen: screen, index: idx)
            
            // Setup cross-screen boundary transit
            overlay.scene.onPetReachBoundary = { [weak self] pet, direction in
                self?.handlePetCrossScreenTransit(pet: pet, fromOverlay: overlay, direction: direction)
            }
            
            overlays.append(overlay)
        }
        
        PetLogger.shared.log("🖥️ Multi-display configured. Total screens: \(overlays.count)")
    }
    
    // MARK: - Smart Hit-Testing & Global Drag
    private func startSmartHitTesting() {
        hitTestTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.checkMouseHitTest()
        }
    }
    
    private func checkMouseHitTest() {
        if isAnyPetDragging { return }
        
        let mouseLoc = NSEvent.mouseLocation
        
        for overlay in overlays {
            if overlay.screen.frame.contains(mouseLoc) {
                let hitPet = overlay.scene.hitTestPet(at: mouseLoc)
                let shouldCatch = (hitPet != nil)
                if overlay.panel.ignoresMouseEvents == shouldCatch {
                    overlay.panel.ignoresMouseEvents = !shouldCatch
                }
            } else {
                if !overlay.panel.ignoresMouseEvents {
                    overlay.panel.ignoresMouseEvents = true
                }
            }
        }
    }
    
    private func handleGlobalMouse(_ event: NSEvent) -> NSEvent? {
        let globalMouse = NSEvent.mouseLocation
        
        switch event.type {
        case .leftMouseDown:
            for overlay in overlays {
                if overlay.screen.frame.contains(globalMouse) {
                    if let pet = overlay.scene.hitTestPet(at: globalMouse) {
                        let petGlobal = getGlobalPosition(of: pet, in: overlay)
                        let offset = CGPoint(x: petGlobal.x - globalMouse.x, y: petGlobal.y - globalMouse.y)
                        
                        draggedPetInfo = (pet, overlay, offset)
                        pet.isBeingDragged = true
                        pet.transitionTo(state: .dragged)
                        isAnyPetDragging = true
                        PetLogger.shared.logInteraction(petId: pet.petId, action: "PickedUp", details: "Global pick up", position: pet.position)
                        return event
                    }
                }
            }
            
        case .leftMouseDragged:
            if let info = draggedPetInfo {
                let newPetGlobal = CGPoint(x: globalMouse.x + info.dragOffsetGlobal.x, y: globalMouse.y + info.dragOffsetGlobal.y)
                
                if let targetOverlay = overlays.first(where: { $0.screen.frame.contains(newPetGlobal) }) {
                    if targetOverlay !== info.sourceOverlay {
                        // Cross-monitor transit during drag!
                        info.sourceOverlay.scene.removePetInstance(info.pet)
                        let localPos = getLocalPosition(globalPos: newPetGlobal, in: targetOverlay)
                        let transferred = targetOverlay.scene.addPet(skin: info.pet.skin, position: localPos, id: info.pet.petId)
                        transferred.scaleMultiplier = info.pet.scaleMultiplier
                        transferred.isBeingDragged = true
                        transferred.transitionTo(state: .dragged)
                        
                        draggedPetInfo = (transferred, targetOverlay, info.dragOffsetGlobal)
                    } else {
                        info.pet.position = getLocalPosition(globalPos: newPetGlobal, in: info.sourceOverlay)
                    }
                }
            }
            
        case .leftMouseUp:
            if let info = draggedPetInfo {
                info.pet.isBeingDragged = false
                info.pet.transitionTo(state: .falling)
                draggedPetInfo = nil
                isAnyPetDragging = false
                PetLogger.shared.logInteraction(petId: info.pet.petId, action: "Dropped", details: "Global drop", position: info.pet.position)
            }
            
        default: break
        }
        return event
    }
    
    private func getGlobalPosition(of pet: PetNode, in overlay: ScreenOverlay) -> CGPoint {
        return CGPoint(x: overlay.screen.frame.minX + pet.position.x, y: overlay.screen.frame.minY + pet.position.y)
    }
    
    private func getLocalPosition(globalPos: CGPoint, in overlay: ScreenOverlay) -> CGPoint {
        return CGPoint(x: globalPos.x - overlay.screen.frame.minX, y: globalPos.y - overlay.screen.frame.minY)
    }
    
    // MARK: - Cross-Screen Transit
    private func handlePetCrossScreenTransit(pet: PetNode, fromOverlay: ScreenOverlay, direction: Direction) {
        let fromFrame = fromOverlay.screen.frame
        
        // Find adjacent target screen based on geometry
        var targetOverlay: ScreenOverlay?
        var newPosition: CGPoint = pet.position
        
        switch direction {
        case .north:
            // Find screen positioned above
            targetOverlay = overlays.first { $0 !== fromOverlay && $0.screen.frame.minY >= fromFrame.maxY - 100 }
            if let target = targetOverlay {
                let xRatio = pet.position.x / fromOverlay.scene.size.width
                newPosition = CGPoint(x: xRatio * target.scene.size.width, y: 50)
            }
            
        case .south:
            // Find screen positioned below
            targetOverlay = overlays.first { $0 !== fromOverlay && $0.screen.frame.maxY <= fromFrame.minY + 100 }
            if let target = targetOverlay {
                let xRatio = pet.position.x / fromOverlay.scene.size.width
                newPosition = CGPoint(x: xRatio * target.scene.size.width, y: target.scene.size.height - 60)
            }
            
        case .east:
            // Find screen to the right
            targetOverlay = overlays.first { $0 !== fromOverlay && $0.screen.frame.minX >= fromFrame.maxX - 100 }
            if let target = targetOverlay {
                let yRatio = pet.position.y / fromOverlay.scene.size.height
                newPosition = CGPoint(x: 50, y: yRatio * target.scene.size.height)
            }
            
        case .west:
            // Find screen to the left
            targetOverlay = overlays.first { $0 !== fromOverlay && $0.screen.frame.maxX <= fromFrame.minX + 100 }
            if let target = targetOverlay {
                let yRatio = pet.position.y / fromOverlay.scene.size.height
                newPosition = CGPoint(x: target.scene.size.width - 50, y: yRatio * target.scene.size.height)
            }
        }
        
        guard let dest = targetOverlay else { return }
        
        PetLogger.shared.logScreenTransit(
            petId: pet.petId,
            from: fromOverlay.screenName,
            to: dest.screenName,
            newPos: newPosition
        )
        
        // Transfer pet node across scenes
        let currentSkin = pet.skin
        let currentScale = pet.scaleMultiplier
        fromOverlay.scene.removePetInstance(pet)
        let transferred = dest.scene.addPet(skin: currentSkin, position: newPosition, id: pet.petId)
        transferred.scaleMultiplier = currentScale
    }
    
    public func show() {
        for overlay in overlays {
            overlay.panel.orderFrontRegardless()
        }
    }
    
    public func hide() {
        for overlay in overlays {
            overlay.panel.orderOut(nil)
        }
    }
    
    public func setOpacity(_ alpha: CGFloat) {
        for overlay in overlays {
            overlay.setOpacity(alpha)
        }
    }
    
    @objc private func screenParametersChanged() {
        PetLogger.shared.log("🖥️ Display layout reconfigured...")
        setupOverlays()
    }
    
    @objc private func activeSpaceDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for overlay in self.overlays {
                overlay.panel.orderFrontRegardless()
                overlay.skView.isPaused = false
            }
        }
    }
    
    deinit {
        hitTestTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
