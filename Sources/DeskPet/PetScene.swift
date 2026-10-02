import AppKit
import SpriteKit

public class PetScene: SKScene {
    public private(set) var pets: [PetNode] = []
    public var windowRects: [CGRect] = []
    public var screenName: String = "Display"
    
    public var onPetReachBoundary: ((PetNode, Direction) -> Void)?
    public var onDragStatusChanged: ((Bool) -> Void)?
    
    private var frameTimer: Timer?
    private var lastStepTime: CFTimeInterval = CACurrentMediaTime()
    private var draggedPet: PetNode?
    private var dragOffset: CGPoint = .zero
    
    public override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        view.isPaused = false
        
        // Guarantee 60fps simulation even when window is non-key and unfocused
        frameTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepSimulation()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.frameTimer = timer
    }
    
    public func addPet(skin: PetSkin, position: CGPoint? = nil, id: String? = nil) -> PetNode {
        let petId = id ?? "Pet-\(pets.count + 1)"
        let pet = PetNode(skin: skin, petId: petId)
        pet.currentScreenName = screenName
        let initPos = position ?? CGPoint(x: CGFloat.random(in: 120...max(200, size.width - 120)), y: 60)
        pet.position = initPos
        pets.append(pet)
        addChild(pet)
        PetLogger.shared.log("✨ [\(petId)] Spawned on [\(screenName)] at (\(Int(initPos.x)), \(Int(initPos.y)))")
        return pet
    }
    
    public func removePet(at index: Int) {
        guard index >= 0 && index < pets.count else { return }
        let pet = pets.remove(at: index)
        pet.removeFromParent()
    }
    
    public func removePetInstance(_ pet: PetNode) {
        if let idx = pets.firstIndex(where: { $0 === pet }) {
            pets.remove(at: idx)
            pet.removeFromParent()
        }
    }
    
    public func updateWindows(_ windows: [CGRect]) {
        self.windowRects = windows
    }
    
    // MARK: - Continuous Frame Simulation
    public override func update(_ currentTime: TimeInterval) {
        stepSimulation()
    }
    
    public func stepSimulation() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastStepTime, 0.1)
        guard dt >= 0.008 else { return } // Cap around 120fps max
        lastStepTime = now
        
        let localMousePos = getLocalMousePosition()
        
        for pet in pets {
            pet.currentScreenName = screenName
            pet.update(
                deltaTime: dt,
                screenBounds: frame,
                windowRects: windowRects,
                localMousePos: localMousePos,
                onReachBoundary: { [weak self] p, dir in
                    self?.onPetReachBoundary?(p, dir)
                }
            )
        }
    }
    
    private func getLocalMousePosition() -> CGPoint? {
        guard let window = view?.window else { return nil }
        let globalMouse = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: globalMouse)
        let scenePoint = convertPoint(fromView: windowPoint)
        if frame.contains(scenePoint) {
            return scenePoint
        }
        return nil
    }
    
    // MARK: - Mouse Drag & Drop
    public func hitTestPet(at globalPoint: CGPoint) -> PetNode? {
        guard let window = view?.window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: globalPoint)
        let scenePoint = convertPoint(fromView: windowPoint)
        
        for pet in pets.reversed() {
            if pet.hitTestBounds().contains(scenePoint) {
                return pet
            }
        }
        return nil
    }
    

}
