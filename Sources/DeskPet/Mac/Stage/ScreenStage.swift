import AppKit
import SpriteKit

/// 한 무대에 그릴 펫 하나의 모습 (전역 좌표)
struct PetDrawing {
    let id: String
    let frame: SpriteFrame<SKTexture>
    /// 스프라이트 칸의 전역 좌표 사각형
    let rect: CGRect
    /// 있으면 숨쉬듯 세로로 들썩이는 위상
    let breathPhase: Double?
    let speech: Speech?
    /// 스킬 도약 꼬리 입자 스타일
    let trail: SkillStyle?
    /// 발 위치와 몸 높이 (입자 위치용)
    let foot: CGPoint
    let bodyHeight: CGFloat
    /// 말풍선 꼬리가 가리킬 머리 위 지점
    let speechAnchor: CGPoint
    /// 불투명도 (모니터 건너가기)
    var alpha: CGFloat = 1
    /// rect 안에서 위아래를 뒤집어 그림 (거꾸로 빼꼼)
    var upsideDown = false
    /// 이 높이(전역 y)보다 위는 그리지 않음
    var hiddenAbove: CGFloat?
    /// 쓰고 있는 모자와 자리
    var hat: (kind: HatKind, frame: HatFrame)?
    /// 앞손에 든 물건과 자리 (Lv.4)
    var held: (kind: ItemKind, rect: CGRect)?
    /// 몸을 돌려 그리는 각도 (공중제비)
    var rotation: CGFloat = 0
    /// 걸을 때 반짝 발자국 (Lv.5)
    var sparkles = false
    /// 발자국 색 단계 (0 기본, 1 분홍, 2 금색)
    var sparkleTier = 0

    /// rect 중 그려지는 아래쪽 비율 (0이면 다 가려짐)
    var shownShare: CGFloat {
        guard let hiddenAbove else { return 1 }
        return min(max((hiddenAbove - rect.minY) / rect.height, 0), 1)
    }
}

/// This object is responsible for drawing the pets that overlap one display,
/// on a transparent panel that floats above other windows on every Space and lets clicks pass through.
final class ScreenStage {
    let area: ScreenArea
    private let panel: NSPanel
    private let view: SKView
    private let scene: SKScene
    private var sprites: [String: SKSpriteNode] = [:]
    private var bubbles: [String: SpeechBubbleNode] = [:]
    private var trails: [String: SkillTrailNode] = [:]
    private var thrown: [String: SKSpriteNode] = [:]
    private var found: [String: SKSpriteNode] = [:]
    private var hats: [String: SKSpriteNode] = [:]
    private var heldNodes: [String: SKSpriteNode] = [:]
    /// 펫별 다음 발자국까지 남은 시간
    private var stepClock: [String: TimeInterval] = [:]
    private var glints: [String: SKSpriteNode] = [:]

    init(area: ScreenArea) {
        self.area = area
        let frame = area.frame

        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.canHide = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        view = SKView(frame: CGRect(origin: .zero, size: frame.size))
        view.allowsTransparency = true
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.preferredFramesPerSecond = 60

        scene = SKScene(size: frame.size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        scene.anchorPoint = .zero
        view.presentScene(scene)

        panel.contentView = view
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// 마우스를 받을지 (펫 위에 커서가 있을 때만 받음)
    var catchesMouse: Bool {
        get { !panel.ignoresMouseEvents }
        set { if panel.ignoresMouseEvents == newValue { panel.ignoresMouseEvents = !newValue } }
    }

    func setOpacity(_ alpha: CGFloat) {
        panel.alphaValue = alpha
    }

    func bringToFront() {
        panel.orderFrontRegardless()
        view.isPaused = false
    }

    /// 이 모니터에 걸친 펫과 무기만 그림. 위치는 화면 픽셀 격자에 맞춤
    func render(_ drawings: [PetDrawing], projectiles: [ProjectileDrawing] = [], items: [ItemDrawing] = []) {
        renderProjectiles(projectiles)
        renderItems(items)
        let visible = drawings.filter { $0.rect.intersects(area.frame) }
        let liveIDs = Set(visible.map(\.id))
        for (id, node) in sprites where !liveIDs.contains(id) {
            node.removeFromParent()
            sprites[id] = nil
        }

        for drawing in visible {
            let node = sprites[drawing.id] ?? makeSprite(id: drawing.id)
            let shown = drawing.shownShare
            node.isHidden = shown <= 0
            guard shown > 0 else { continue }
            node.texture = Self.texture(of: drawing, shown: shown)
            node.size = CGSize(width: drawing.rect.width, height: drawing.rect.height * shown)
            node.xScale = drawing.frame.mirrored ? -1 : 1
            node.alpha = drawing.alpha
            // 발 기준으로 세로만 살짝 줄었다 늘어남. 뒤집힌 몸은 보이는 윗줄에서 아래로 그림
            let breath = drawing.breathPhase.map { 1 - 0.04 * (0.5 + 0.5 * sin($0 * 2.2)) } ?? 1
            node.yScale = drawing.upsideDown ? -breath : breath
            let baseY = drawing.upsideDown ? drawing.rect.minY + drawing.rect.height * shown : drawing.rect.minY
            if drawing.rotation != 0 {
                // 공중제비는 몸 가운데를 축으로 돎
                node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                node.zRotation = drawing.rotation
                node.position = CGPoint(x: snap(drawing.rect.midX - area.frame.minX), y: snap(drawing.rect.midY - area.frame.minY))
            } else {
                node.anchorPoint = CGPoint(x: 0.5, y: 0)
                node.zRotation = 0
                node.position = CGPoint(
                    x: snap(drawing.rect.midX - area.frame.minX),
                    y: snap(baseY - area.frame.minY)
                )
            }
        }
        renderHats(visible)
        renderHeld(visible)
        renderFootsteps(drawings)
        renderBubbles(drawings)
        renderTrails(drawings)
    }

    /// 펫 머리 위 모자. 숨쉬기로 몸이 줄면 같이 내려오고, 창 윗변 뒤로 숨은 부분은 잘림
    private func renderHats(_ drawings: [PetDrawing]) {
        let wearing = drawings.filter { $0.hat != nil && $0.shownShare > 0 }
        let liveIDs = Set(wearing.map(\.id))
        for (id, node) in hats where !liveIDs.contains(id) {
            node.removeFromParent()
            hats[id] = nil
        }
        for drawing in wearing {
            guard let (kind, frame) = drawing.hat else { continue }
            let breath = drawing.breathPhase.map { 1 - 0.04 * (0.5 + 0.5 * sin($0 * 2.2)) } ?? 1
            let drop = (1 - breath) * drawing.bodyHeight * (frame.flipY ? -1 : 1)
            var rect = frame.rect.offsetBy(dx: 0, dy: -drop)
            var shown: CGFloat = 1
            if let line = drawing.hiddenAbove {
                shown = min(max((line - rect.minY) / rect.height, 0), 1)
            }
            let node = hats[drawing.id] ?? makeHat(id: drawing.id)
            node.isHidden = shown <= 0
            guard shown > 0 else { continue }
            let base = ProjectileArt.texture(for: kind)
            if shown < 1 {
                let texture = SKTexture(rect: CGRect(x: 0, y: frame.flipY ? 1 - shown : 0, width: 1, height: shown), in: base)
                texture.filteringMode = .nearest
                node.texture = texture
                rect.size.height *= shown
            } else {
                node.texture = base
            }
            node.size = rect.size
            node.xScale = frame.flipX ? -1 : 1
            node.yScale = frame.flipY ? -1 : 1
            node.alpha = drawing.alpha
            place(node, at: CGPoint(x: rect.midX, y: rect.midY), turning: drawing)
        }
    }

    /// 몸이 돌고 있으면 몸 가운데를 축으로 같이 돌려 놓음
    private func place(_ node: SKSpriteNode, at center: CGPoint, turning drawing: PetDrawing) {
        var point = center
        if drawing.rotation != 0 {
            let pivot = CGPoint(x: drawing.rect.midX, y: drawing.rect.midY)
            let dx = center.x - pivot.x, dy = center.y - pivot.y
            let c = cos(drawing.rotation), s = sin(drawing.rotation)
            point = CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
        }
        node.zRotation = drawing.rotation
        node.position = CGPoint(x: snap(point.x - area.frame.minX), y: snap(point.y - area.frame.minY))
    }

    /// 앞손에 든 물건 (Lv.4)
    private func renderHeld(_ drawings: [PetDrawing]) {
        let holding = drawings.filter { $0.held != nil }
        let liveIDs = Set(holding.map(\.id))
        for (id, node) in heldNodes where !liveIDs.contains(id) {
            node.removeFromParent()
            heldNodes[id] = nil
        }
        for drawing in holding {
            guard let (kind, rect) = drawing.held else { continue }
            let node = heldNodes[drawing.id] ?? makeHeld(id: drawing.id)
            node.texture = ProjectileArt.texture(for: kind)
            node.size = rect.size
            node.alpha = drawing.alpha
            node.yScale = drawing.upsideDown ? -1 : 1
            place(node, at: CGPoint(x: rect.midX, y: rect.midY), turning: drawing)
        }
    }

    private func makeHeld(id: String) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.zPosition = 2
        scene.addChild(node)
        heldNodes[id] = node
        return node
    }

    /// 걸을 때 발밑에 옅은 반짝임 (Lv.5). 발이 있는 모니터에서만
    private func renderFootsteps(_ drawings: [PetDrawing]) {
        for drawing in drawings where drawing.sparkles && area.frame.contains(drawing.foot) {
            let left = (stepClock[drawing.id] ?? 0) - 1.0 / 60
            guard left <= 0 else {
                stepClock[drawing.id] = left
                continue
            }
            stepClock[drawing.id] = 0.15
            guard Bool.random() else { continue }
            let spark = SKSpriteNode(texture: ProjectileArt.burst)
            let side = drawing.rect.width / 48 * 6
            spark.size = CGSize(width: side, height: side)
            spark.alpha = 0.55 * drawing.alpha
            spark.zPosition = -1
            if drawing.sparkleTier > 0, drawing.sparkleTier < Self.footstepTints.count, let tint = Self.footstepTints[drawing.sparkleTier] {
                spark.color = tint
                spark.colorBlendFactor = 0.75
            }
            spark.position = CGPoint(x: drawing.foot.x - area.frame.minX + CGFloat.random(in: -4...4), y: drawing.foot.y - area.frame.minY + 2)
            scene.addChild(spark)
            spark.run(.sequence([.group([.fadeOut(withDuration: 0.6), .moveBy(x: 0, y: 6, duration: 0.6)]), .removeFromParent()]))
        }
    }

    private func makeHat(id: String) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.zPosition = 1
        scene.addChild(node)
        hats[id] = node
        return node
    }

    /// 날아가는 무기는 돌며 날고, 닿으면 반짝임이 커지며 사라짐
    private func renderProjectiles(_ drawings: [ProjectileDrawing]) {
        let visible = drawings.filter { area.frame.insetBy(dx: -40, dy: -40).contains($0.center) }
        let liveIDs = Set(visible.map(\.id))
        for (id, node) in thrown where !liveIDs.contains(id) {
            node.removeFromParent()
            thrown[id] = nil
        }
        for drawing in visible {
            let node = thrown[drawing.id] ?? makeProjectile(id: drawing.id)
            let side = 8 * drawing.scale
            if let burst = drawing.burst {
                node.texture = ProjectileArt.burst
                node.size = CGSize(width: side * (1 + CGFloat(burst)), height: side * (1 + CGFloat(burst)))
                node.alpha = 1 - CGFloat(burst)
                node.zRotation = 0
            } else {
                node.texture = ProjectileArt.texture(for: drawing.kind)
                node.size = CGSize(width: side, height: side)
                node.alpha = 1
                node.zRotation = -drawing.rotation
            }
            node.position = CGPoint(x: snap(drawing.center.x - area.frame.minX), y: snap(drawing.center.y - area.frame.minY))
        }
    }

    /// 떨어진 물건. 드문 물건과 클릭한 물건은 뒤에 반짝임
    private func renderItems(_ drawings: [ItemDrawing]) {
        let visible = drawings.filter { area.frame.insetBy(dx: -20, dy: -20).intersects($0.rect) }
        let liveIDs = Set(visible.map(\.id))
        for (id, node) in found where !liveIDs.contains(id) {
            node.removeFromParent()
            found[id] = nil
            glints[id]?.removeFromParent()
            glints[id] = nil
        }
        for drawing in visible {
            let node = found[drawing.id] ?? makeItem(id: drawing.id)
            node.texture = ProjectileArt.texture(for: drawing.kind)
            node.size = drawing.rect.size
            node.alpha = drawing.alpha
            node.position = CGPoint(x: snap(drawing.rect.midX - area.frame.minX), y: snap(drawing.rect.minY - area.frame.minY))
            let glint = glints[drawing.id] ?? makeGlint(id: drawing.id)
            glint.isHidden = drawing.sparkle <= 0
            glint.alpha = drawing.sparkle * drawing.alpha
            glint.size = CGSize(width: drawing.rect.width * 1.8, height: drawing.rect.height * 1.8)
            glint.position = CGPoint(x: node.position.x, y: node.position.y + drawing.rect.height / 2)
            if drawing.trail && Bool.random() { sparkle(at: CGPoint(x: drawing.rect.midX, y: drawing.rect.midY), side: drawing.rect.width) }
        }
    }

    /// 발자국 색 단계별 물들임 (0단계는 원래 노란색)
    private static let footstepTints: [NSColor?] = [nil, NSColor(red: 1, green: 0.55, blue: 0.78, alpha: 1), NSColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)]

    /// 드문 물건이 날아간 자리에 잠깐 남는 반짝임
    private func sparkle(at point: CGPoint, side: CGFloat) {
        let spark = SKSpriteNode(texture: ProjectileArt.burst)
        spark.size = CGSize(width: side, height: side)
        spark.alpha = 0.8
        spark.zPosition = 3
        spark.position = CGPoint(x: point.x - area.frame.minX + CGFloat.random(in: -3...3), y: point.y - area.frame.minY + CGFloat.random(in: -3...3))
        scene.addChild(spark)
        spark.run(.sequence([.group([.fadeOut(withDuration: 0.5), .scale(to: 0.3, duration: 0.5)]), .removeFromParent()]))
    }

    private func makeItem(id: String) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.zPosition = 4
        scene.addChild(node)
        found[id] = node
        return node
    }

    private func makeGlint(id: String) -> SKSpriteNode {
        let node = SKSpriteNode(texture: ProjectileArt.burst)
        node.zPosition = 3
        scene.addChild(node)
        glints[id] = node
        return node
    }

    private func makeProjectile(id: String) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.zPosition = 5
        scene.addChild(node)
        thrown[id] = node
        return node
    }

    /// 꼬리 입자는 발이 있는 모니터에서만 새로 뿜음
    private func renderTrails(_ drawings: [PetDrawing]) {
        let liveIDs = Set(drawings.map(\.id))
        for (id, node) in trails where !liveIDs.contains(id) {
            node.removeFromParent()
            trails[id] = nil
        }
        for drawing in drawings {
            let here = area.frame.contains(drawing.foot)
            guard let style = drawing.trail, here else {
                trails[drawing.id]?.emit(nil)
                continue
            }
            let node = trails[drawing.id] ?? makeTrail(id: drawing.id)
            node.emit(style)
            node.position = CGPoint(
                x: drawing.foot.x - area.frame.minX,
                y: drawing.foot.y - area.frame.minY + node.anchorOffset(bodyHeight: drawing.bodyHeight)
            )
        }
    }

    private func makeTrail(id: String) -> SkillTrailNode {
        let node = SkillTrailNode()
        node.zPosition = -1
        node.targetNode = scene
        scene.addChild(node)
        trails[id] = node
        return node
    }

    /// 말풍선은 꼬리 지점이 있는 모니터 한 곳에만 그림
    private func renderBubbles(_ drawings: [PetDrawing]) {
        let speaking = drawings.filter { $0.speech != nil && area.frame.contains($0.speechAnchor) }
        let liveIDs = Set(speaking.map(\.id))
        for (id, node) in bubbles where !liveIDs.contains(id) {
            node.removeFromParent()
            bubbles[id] = nil
        }
        for drawing in speaking {
            guard let speech = drawing.speech else { continue }
            let bubble = bubbles[drawing.id] ?? makeBubble(id: drawing.id)
            bubble.show(speech)
            let anchor = CGPoint(x: snap(drawing.speechAnchor.x - area.frame.minX), y: snap(drawing.speechAnchor.y - area.frame.minY))
            bubble.place(pointingAt: anchor, within: 0...area.frame.width)
        }
    }

    private func makeBubble(id: String) -> SpeechBubbleNode {
        let bubble = SpeechBubbleNode()
        bubble.zPosition = 10
        scene.addChild(bubble)
        bubbles[id] = bubble
        return bubble
    }

    func close() {
        view.isPaused = true
        panel.orderOut(nil)
        panel.close()
    }

    private func makeSprite(id: String) -> SKSpriteNode {
        let node = SKSpriteNode()
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        scene.addChild(node)
        sprites[id] = node
        return node
    }

    /// 가려진 만큼 잘라 낸 텍스처. 바로 선 몸은 아래쪽, 뒤집힌 몸은 머리가 있는 위쪽을 남김
    private static func texture(of drawing: PetDrawing, shown: CGFloat) -> SKTexture {
        guard shown < 1 else { return drawing.frame.texture }
        let part = CGRect(x: 0, y: drawing.upsideDown ? 1 - shown : 0, width: 1, height: shown)
        let texture = SKTexture(rect: part, in: drawing.frame.texture)
        texture.filteringMode = .nearest
        return texture
    }

    private func snap(_ value: CGFloat) -> CGFloat {
        (value * area.backingScale).rounded() / area.backingScale
    }
}
