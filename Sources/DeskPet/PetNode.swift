import AppKit
import SpriteKit

public enum PetState: String {
    case idle
    case walking
    case climbing
    case sliding
    case jumping
    case falling
    case peek
    case action
    case mouseFollowing
    case dragged
}

public class PetNode: SKNode {
    public var skin: PetSkin {
        didSet {
            applySkin()
        }
    }
    
    public let petId: String
    public private(set) var currentState: PetState = .idle
    public private(set) var currentDirection: Direction = .east
    public var currentScreenName: String = "Display"
    
    private let spriteNode: SKSpriteNode
    public let baseSize: CGSize = CGSize(width: 48, height: 48) // Fixed 48x48 pixel size
    
    public var scaleMultiplier: CGFloat = 1.6 {
        didSet {
            updateScale()
        }
    }
    
    // Physics & Movement parameters
    public var velocity: CGPoint = .zero
    private let walkSpeed: CGFloat = 85.0
    private let climbSpeed: CGFloat = 65.0
    private let slideSpeed: CGFloat = 130.0
    private let gravity: CGFloat = 550.0
    private let jumpStrength: CGFloat = 300.0
    
    // State timer
    private var stateDuration: TimeInterval = 0
    private var stateTimer: TimeInterval = 0
    
    // Independent Frame Stepper Animation System
    private var animationTickTimer: TimeInterval = 0
    private var currentFrameIndex: Int = 0
    private var activeFrames: [SKTexture] = []
    private var frameInterval: TimeInterval = 0.12
    
    // Platform & Wall interaction
    private var currentPlatform: CGRect?
    private var currentWall: CGRect?
    private var wallSide: Direction = .east
    
    // Drag & Drop
    public var isBeingDragged: Bool = false
    
    public init(skin: PetSkin, petId: String = "Pet-1") {
        self.skin = skin
        self.petId = petId
        self.spriteNode = SKSpriteNode()
        super.init()
        
        addChild(spriteNode)
        updateScale()
        applySkin()
        transitionTo(state: .idle, duration: Double.random(in: 0.6...1.2))
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func applySkin() {
        updateScale()
        updateAnimationFrames()
    }
    
    // Absolute Size Enforcement:
    // spriteNode.size holds the absolute display dimensions (width, height).
    // xScale and yScale are strictly used for directional flipping (-1.0 / +1.0) and NEVER for scaling!
    private func updateScale() {
        let fixedDim = baseSize.width * scaleMultiplier
        spriteNode.size = CGSize(width: fixedDim, height: fixedDim)
        let flipX = (currentDirection == .west)
        spriteNode.xScale = flipX ? -1.0 : 1.0
        spriteNode.yScale = 1.0
    }
    
    // MARK: - State Machine
    public func transitionTo(state: PetState, duration: TimeInterval = 0) {
        let oldState = currentState
        currentState = state
        stateDuration = duration
        stateTimer = 0
        currentFrameIndex = 0
        animationTickTimer = 0
        
        PetLogger.shared.logStateChange(
            petId: petId,
            from: oldState.rawValue,
            to: state.rawValue,
            position: position,
            screen: currentScreenName
        )
        
        switch state {
        case .idle:
            velocity = .zero
            currentDirection = Bool.random() ? .east : .west
            
        case .walking:
            let speed = (currentDirection == .east ? walkSpeed : -walkSpeed)
            velocity = CGPoint(x: speed, y: 0)
            
        case .mouseFollowing:
            let speed = (currentDirection == .east ? walkSpeed : -walkSpeed)
            velocity = CGPoint(x: speed, y: 0)
            
        case .climbing:
            velocity = CGPoint(x: 0, y: climbSpeed)
            
        case .sliding:
            velocity = CGPoint(x: 0, y: -slideSpeed)
            
        case .jumping:
            let jumpDir: CGFloat = (currentDirection == .east ? 1.0 : -1.0)
            velocity = CGPoint(x: jumpDir * walkSpeed * 1.3, y: jumpStrength)
            
        case .falling:
            velocity.x *= 0.6
            
        case .peek:
            velocity = .zero
            
        case .action:
            velocity = .zero
            
        case .dragged:
            velocity = .zero
        }
        
        updateScale()
        updateAnimationFrames()
    }
    
    // MARK: - Frame Stepper Animation System
    private func updateAnimationFrames() {
        switch currentState {
        case .idle, .peek:
            let texture = skin.idleTextures[currentDirection] ?? skin.idleTextures[.south]
            activeFrames = texture != nil ? [texture!] : []
            frameInterval = 0.5
            
        case .walking, .mouseFollowing:
            let dir = currentDirection == .west ? .east : currentDirection
            var frames = skin.walkTextures[dir] ?? skin.walkTextures[.south] ?? []
            if frames.isEmpty, let southFrames = skin.walkTextures[.south] {
                frames = southFrames
            }
            activeFrames = frames
            frameInterval = 0.11
            
        case .climbing:
            activeFrames = skin.walkTextures[.north] ?? skin.walkTextures[.south] ?? []
            frameInterval = 0.13
            
        case .sliding:
            activeFrames = skin.walkTextures[.south] ?? []
            frameInterval = 0.10
            
        case .falling, .jumping, .dragged:
            let texture = skin.idleTextures[.south] ?? skin.idleTextures[currentDirection]
            activeFrames = texture != nil ? [texture!] : []
            frameInterval = 0.5
            
        case .action:
            let dir = currentDirection == .west ? .east : currentDirection
            activeFrames = skin.actionTextures[dir] ?? skin.actionTextures[.south] ?? []
            frameInterval = 0.10
        }
        
        if let first = activeFrames.first {
            spriteNode.texture = first
            updateScale() // Immediately lock size
        }
    }
    
    private func stepAnimationFrame(deltaTime: TimeInterval) {
        guard !activeFrames.isEmpty else { return }
        
        if activeFrames.count == 1 {
            spriteNode.texture = activeFrames[0]
            updateScale()
            return
        }
        
        animationTickTimer += deltaTime
        if animationTickTimer >= frameInterval {
            animationTickTimer = 0
            currentFrameIndex = (currentFrameIndex + 1) % activeFrames.count
            spriteNode.texture = activeFrames[currentFrameIndex]
            updateScale() // Always enforce fixed size upon texture change
            
            if currentState == .action && currentFrameIndex == activeFrames.count - 1 {
                transitionTo(state: .idle, duration: Double.random(in: 0.8...1.5))
            }
        }
    }
    
    // Hit-testing for Drag & Drop
    public func hitTestBounds() -> CGRect {
        let petSize = baseSize.width * scaleMultiplier
        return CGRect(
            x: position.x - petSize / 2.0,
            y: position.y - petSize / 2.0,
            width: petSize,
            height: petSize
        )
    }
    
    // MARK: - Frame Update
    public func update(
        deltaTime: TimeInterval,
        screenBounds: CGRect,
        windowRects: [CGRect],
        localMousePos: CGPoint?,
        onReachBoundary: ((PetNode, Direction) -> Void)?
    ) {
        stepAnimationFrame(deltaTime: deltaTime)
        
        if isBeingDragged {
            return
        }
        
        stateTimer += deltaTime
        
        let petWidth = baseSize.width * scaleMultiplier
        let petHeight = baseSize.height * scaleMultiplier
        let halfW = petWidth / 2.0
        let halfH = petHeight / 2.0
        
        let minX = halfW
        let maxX = screenBounds.width - halfW
        let groundY = halfH + 8
        let ceilingY = screenBounds.height - halfH - 8
        
        let footY = position.y - halfH
        
        switch currentState {
        case .dragged:
            break
            
        case .idle:
            if !isOnGroundOrPlatform(windows: windowRects, groundY: groundY, footY: footY) {
                currentPlatform = nil
                transitionTo(state: .falling)
            } else if stateTimer >= stateDuration {
                // Check mouse follow (45% chance)
                if let mouse = localMousePos, Double.random(in: 0...1) < 0.45 {
                    let dx = mouse.x - position.x
                    currentDirection = (dx > 0) ? .east : .west
                    updateScale()
                    let dist = abs(dx)
                    if dist > 35 {
                        PetLogger.shared.logInteraction(petId: petId, action: "FollowMouse", details: "Chasing mouse at x: \(Int(mouse.x))", position: position)
                        transitionTo(state: .mouseFollowing, duration: min(4.0, Double(dist / walkSpeed)))
                        return
                    }
                }
                
                let rand = Int.random(in: 0...100)
                if rand < 40 {
                    currentDirection = Bool.random() ? .east : .west
                    updateScale()
                    transitionTo(state: .walking, duration: Double.random(in: 1.0...4.5))
                } else if rand < 55 {
                    transitionTo(state: .jumping)
                } else if rand < 65 {
                    transitionTo(state: .jumping)
                    velocity.x *= 1.5 // Jump further
                } else if rand < 75 {
                    transitionTo(state: .peek, duration: Double.random(in: 0.8...2.5))
                } else if rand < 90 {
                    transitionTo(state: .action)
                } else {
                    currentDirection = Bool.random() ? .east : .west
                    updateScale()
                    transitionTo(state: .walking, duration: Double.random(in: 0.5...1.5))
                    velocity.x = (currentDirection == .east ? walkSpeed * 2.5 : -walkSpeed * 2.5) // Sprint
                }
            }
            
        case .mouseFollowing:
            if let mouse = localMousePos {
                let dx = mouse.x - position.x
                currentDirection = (dx > 0) ? .east : .west
                updateScale()
                let step = (currentDirection == .east ? walkSpeed : -walkSpeed) * CGFloat(deltaTime)
                position.x += step
                
                if position.x <= minX { position.x = minX; transitionTo(state: .idle, duration: 1.0) }
                if position.x >= maxX { position.x = maxX; transitionTo(state: .idle, duration: 1.0) }
                
                if let platform = currentPlatform {
                    if position.x < platform.minX - 5 || position.x > platform.maxX + 5 {
                        currentPlatform = nil
                        transitionTo(state: .falling)
                    }
                }
                
                if abs(mouse.x - position.x) <= 25 || stateTimer >= stateDuration {
                    transitionTo(state: .idle, duration: Double.random(in: 0.8...1.5))
                }
            } else {
                transitionTo(state: .walking, duration: 2.0)
            }
            
        case .peek:
            if stateTimer >= stateDuration {
                transitionTo(state: .walking, duration: Double.random(in: 2.0...4.0))
            }
            
        case .walking:
            position.x += velocity.x * CGFloat(deltaTime)
            
            // Screen edge check
            if position.x <= minX {
                position.x = minX
                onReachBoundary?(self, .west)
                currentDirection = .east
                updateScale()
                transitionTo(state: .walking, duration: Double.random(in: 2.0...4.0))
            } else if position.x >= maxX {
                position.x = maxX
                onReachBoundary?(self, .east)
                currentDirection = .west
                updateScale()
                transitionTo(state: .walking, duration: Double.random(in: 2.0...4.0))
            }
            
            // 1. Check if walking off a platform ledge (CLIFF / DROP)
            if let platform = currentPlatform {
                let offLeft = position.x < platform.minX - 2
                let offRight = position.x > platform.maxX + 2
                if offLeft || offRight {
                    currentPlatform = nil
                    velocity.x = (offRight ? 40.0 : -40.0)
                    PetLogger.shared.logInteraction(petId: petId, action: "CliffJump", details: "Plunged off window ledge", position: position)
                    transitionTo(state: .falling)
                    return
                }
            } else {
                if position.y > groundY + 8 && !checkIsOnAnyPlatform(windows: windowRects, footY: footY) {
                    transitionTo(state: .falling)
                    return
                }
            }
            
            // 2. Precise Geometric Wall Collision
            for win in windowRects {
                if let cur = currentPlatform, cur == win { continue }
                
                let rightEdge = position.x + halfW
                let leftEdge = position.x - halfW
                let topEdge = position.y + halfH
                let bottomEdge = position.y - halfH
                
                let isHittingLeftWall = (currentDirection == .east) &&
                    rightEdge >= win.minX && rightEdge <= win.minX + 16 &&
                    topEdge > win.minY + 4 && bottomEdge < win.maxY - 4
                
                let isHittingRightWall = (currentDirection == .west) &&
                    leftEdge <= win.maxX && leftEdge >= win.maxX - 16 &&
                    topEdge > win.minY + 4 && bottomEdge < win.maxY - 4
                
                if isHittingLeftWall || isHittingRightWall {
                    let hitWall = win
                    PetLogger.shared.logInteraction(petId: petId, action: "HitWall", details: "Hit window edge at x: \(Int(position.x))", position: position)
                    
                    // Snap to wall
                    position.x = isHittingLeftWall ? win.minX - halfW : win.maxX + halfW
                    
                    if Double.random(in: 0...1) < 0.7 {
                        currentWall = hitWall
                        wallSide = currentDirection
                        transitionTo(state: .climbing)
                    } else {
                        currentDirection = (currentDirection == .east ? .west : .east)
                        updateScale()
                        transitionTo(state: .walking, duration: Double.random(in: 1.5...3.0))
                    }
                    break
                }
            }
            
            if stateTimer >= stateDuration && currentState == .walking {
                transitionTo(state: .idle, duration: Double.random(in: 0.6...1.5))
            }
            
        case .climbing:
            position.y += velocity.y * CGFloat(deltaTime)
            
            // Allow enough time to reach the top of tall windows.
            // If it takes extremely long, slide down gracefully instead of jumping into the wall.
            if stateTimer >= 15.0 {
                transitionTo(state: .sliding)
                return
            }
            
            if let wall = currentWall {
                if position.y >= wall.maxY + halfH {
                    position.y = wall.maxY + halfH
                    currentPlatform = wall
                    currentWall = nil
                    currentDirection = (wallSide == .west) ? .east : .west
                    updateScale()
                    PetLogger.shared.logInteraction(petId: petId, action: "LandedOnWindowTop", details: "Reached window top", position: position)
                    transitionTo(state: .walking, duration: Double.random(in: 2.5...5.0))
                }
            } else if position.y >= ceilingY {
                position.y = ceilingY
                onReachBoundary?(self, .north)
                currentWall = nil
                transitionTo(state: .falling)
            }
            
        case .sliding:
            position.y += velocity.y * CGFloat(deltaTime)
            if position.y <= groundY {
                position.y = groundY
                currentWall = nil
                transitionTo(state: .idle, duration: 0.8)
            } else if let wall = currentWall, position.y <= wall.minY + halfH {
                currentWall = nil
                transitionTo(state: .falling)
            }
            
        case .falling:
            velocity.y -= gravity * CGFloat(deltaTime)
            position.y += velocity.y * CGFloat(deltaTime)
            position.x += velocity.x * CGFloat(deltaTime)
            
            let currentFootY = position.y - halfH
            
            if currentFootY <= groundY - halfH {
                position.y = groundY
                velocity = .zero
                currentPlatform = nil
                onReachBoundary?(self, .south)
                transitionTo(state: .idle, duration: 0.6)
                return
            }
            
            let previousFootY = currentFootY - (velocity.y * CGFloat(deltaTime))
            
            for win in windowRects {
                let xRange = (win.minX - 8)...(win.maxX + 8)
                if xRange.contains(position.x) {
                    // Continuous Collision Detection (CCD) against the roof to prevent tunneling
                    if previousFootY >= win.maxY - 4 && currentFootY <= win.maxY + 4 && velocity.y < 0 {
                        position.y = win.maxY + halfH
                        velocity = .zero
                        currentPlatform = win
                        PetLogger.shared.logInteraction(petId: petId, action: "LandedOnPlatform", details: "Landed on window title bar", position: position)
                        transitionTo(state: .idle, duration: 0.6)
                        return
                    }
                }
            }
            
        case .jumping:
            velocity.y -= gravity * CGFloat(deltaTime)
            position.y += velocity.y * CGFloat(deltaTime)
            position.x += velocity.x * CGFloat(deltaTime)
            
            if velocity.y <= 0 {
                transitionTo(state: .falling)
            }
            
        case .action:
            break
        }
        
        position.x = max(minX, min(maxX, position.x))
        position.y = max(groundY, min(ceilingY, position.y))
    }
    
    // MARK: - Collision Helpers
    private func isOnGroundOrPlatform(windows: [CGRect], groundY: CGFloat, footY: CGFloat) -> Bool {
        if position.y <= groundY + 4 { return true }
        return checkIsOnAnyPlatform(windows: windows, footY: footY)
    }
    
    private func checkIsOnAnyPlatform(windows: [CGRect], footY: CGFloat) -> Bool {
        for win in windows {
            if position.x >= win.minX - 8 && position.x <= win.maxX + 8 {
                if abs(footY - win.maxY) <= 12 {
                    currentPlatform = win
                    return true
                }
            }
        }
        return false
    }
}
