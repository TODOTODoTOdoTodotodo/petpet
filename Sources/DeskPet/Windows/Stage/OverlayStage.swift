import Foundation
import WinSDK

/// This object is responsible for drawing the simulation on Windows: one layered overlay per monitor,
/// rebuilt when the monitor layout changes, and every tick the shared scene placed in each overlay's pixels in the
/// macOS stage's layer order: trail and footstep sparkles, pet bodies (feet, mirroring, peeking from behind a window
/// top, breathing, somersaults and transparency as Core decided), hats, held items, dropped items with their glints,
/// thrown weapons with their burst or dust, and speech bubbles on the monitor the pet's head is on. Each tangible
/// pet's grab box and each resting item is made clickable, and only the overlay under one takes the mouse.
final class OverlayStage: PetStage {
    private let instance = GetModuleHandleW(nil)
    private let composer = SceneComposer<WinSprite>.forSkins()
    private let effects = SceneEffects()
    private let art = DotImageCache()
    private let bubbles = BubblePainter()
    private var screens: [(area: ScreenArea, overlay: LayeredOverlay)] = []
    private var areas: [ScreenArea] = []
    private var coordinates = WindowsCoordinates.current()
    private(set) var lastDrawings = 0
    /// 층별로 한 틱에 그린 가장 많은 수 (연기 시험 보고서용)
    private(set) var mostDrawn: [String: Int] = [:]
    /// 펫 전체 투명도 (메뉴의 Opacity). 맥 패널 투명도처럼 말풍선·물건까지 모두에 곱함
    var opacity: CGFloat = 1

    func rebuild(for areas: [ScreenArea]) {
        guard areas != self.areas else { return }
        screens.forEach { $0.overlay.close() }
        coordinates = WindowsCoordinates.current()
        self.areas = areas
        screens = areas.compactMap { area in
            LayeredOverlay(box: coordinates.pixelBox(area.frame, origin: POINT(x: 0, y: 0)), instance: instance).map { (area, $0) }
        }
    }

    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], discreet: Bool) {
        let scene = composer.compose(pets, projectiles: projectiles, items: items, discreet: discreet)
        effects.step(scene)
        lastDrawings = scene.pets.count
        let sparks = effects.sparks
        // 레이어드 창은 투명 픽셀의 클릭을 넘기므로, 다리 사이처럼 빈 곳도 잡히게 잡기 영역을 칠함 (맥 무대와 같은 판정)
        let grabAreas = pets.filter(\.isTangible).map(\.grabRect).filter { !$0.isNull } + items.filter(\.isResting).map(\.hitRect)
        for (area, overlay) in screens {
            var layers = Layers(stage: self, origin: overlay.origin, bounds: overlay.canvas.bounds)
            layers.sparks(sparks.filter { !$0.front })
            scene.pets.forEach { layers.body($0) }
            scene.pets.forEach { layers.hat($0) }
            scene.pets.forEach { layers.held($0) }
            scene.items.forEach { layers.item($0) }
            layers.sparks(sparks.filter(\.front))
            scene.projectiles.forEach { layers.projectile($0) }
            // 말풍선은 꼬리 지점이 있는 모니터 한 곳에만, 그 모니터 너비 안에
            for pet in scene.pets where area.frame.contains(pet.speechAnchor) {
                layers.bubble(pet, within: area.frame.minX...area.frame.maxX)
            }
            overlay.render(layers.sprites, hitAreas: grabAreas.map { coordinates.pixelBox($0, origin: overlay.origin) })
            for (layer, count) in layers.counts { mostDrawn[layer] = max(mostDrawn[layer] ?? 0, count) }
        }
    }

    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {
        let pointer = coordinates.screenPoint(cursor)
        for (_, overlay) in screens {
            let inside = pointer.x >= overlay.origin.x && pointer.x < overlay.origin.x + LONG(overlay.canvas.width)
                && pointer.y >= overlay.origin.y && pointer.y < overlay.origin.y + LONG(overlay.canvas.height)
            overlay.catchesMouse = wantsMouse && inside
        }
    }

    /// 무대별 크기와 보이는 픽셀 수, 층별 그린 수, 말풍선 그리기 결과 (연기 시험 보고서용)
    var summary: [[String: Any]] {
        screens.map {
            ["x": Int($0.overlay.origin.x), "y": Int($0.overlay.origin.y), "width": $0.overlay.canvas.width,
             "height": $0.overlay.canvas.height, "visiblePixels": $0.overlay.canvas.visiblePixelCount]
        }
    }

    var drawReport: [String: Any] {
        ["mostDrawn": mostDrawn, "bubblesPainted": bubbles.painted, "bubblesBadged": bubbles.badged, "bubbleFailures": bubbles.failures,
         "bubbleColorPixels": bubbles.mostColoredPixels]
    }

    func close() {
        screens.forEach { $0.overlay.close() }
        screens = []
    }

    /// This object is responsible for collecting one overlay's sprites for one tick, in drawing order,
    /// converting each decoration's global rectangle to that overlay's pixels.
    private struct Layers {
        let stage: OverlayStage
        let origin: POINT
        /// 이 오버레이의 픽셀 범위 (밖으로 나간 그림은 싣지 않음)
        let bounds: PixelBox
        private(set) var sprites: [OverlaySprite] = []
        private(set) var counts: [String: Int] = [:]

        init(stage: OverlayStage, origin: POINT, bounds: PixelBox) {
            self.stage = stage
            self.origin = origin
            self.bounds = bounds
        }

        private var unit: CGFloat { stage.coordinates.unit }

        private func box(_ rect: CGRect) -> PixelBox {
            stage.coordinates.pixelBox(rect, origin: origin)
        }

        private mutating func add(_ sprite: OverlaySprite, as layer: String) {
            // 돌린 그림은 사각형보다 넓게 그려지므로 반 변만큼 여유를 둠
            let reach = sprite.rotation == 0 ? 0 : max(sprite.box.width, sprite.box.height) / 2
            let padded = PixelBox(x: sprite.box.x - reach, y: sprite.box.y - reach, width: sprite.box.width + reach * 2,
                                  height: sprite.box.height + reach * 2)
            guard !sprite.box.isEmpty, !padded.intersection(bounds).isEmpty else { return }
            var sprite = sprite
            sprite.alpha *= stage.opacity
            sprites.append(sprite)
            counts[layer, default: 0] += 1
        }

        /// 숨쉬기 세로 비율 (발 기준으로 살짝 줄었다 늘어남, 맥과 같은 식)
        private static func breath(_ pet: PetDrawing<WinSprite>) -> CGFloat {
            pet.breathPhase.map { 1 - 0.04 * (0.5 + 0.5 * sin($0 * 2.2)) } ?? 1
        }

        /// 몸이 돌고 있으면 몸 가운데를 축으로 같이 돌린 자리
        private static func turned(_ center: CGPoint, with pet: PetDrawing<WinSprite>) -> CGPoint {
            guard pet.rotation != 0 else { return center }
            let pivot = CGPoint(x: pet.rect.midX, y: pet.rect.midY)
            let dx = center.x - pivot.x, dy = center.y - pivot.y
            let c = cos(pet.rotation), s = sin(pet.rotation)
            return CGPoint(x: pivot.x + dx * c - dy * s, y: pivot.y + dx * s + dy * c)
        }

        mutating func body(_ pet: PetDrawing<WinSprite>) {
            let shown = pet.shownShare
            guard shown > 0 else { return }
            let breath = Self.breath(pet)
            var rect = pet.rect
            if pet.rotation == 0, breath != 1 {
                // 바로 선 몸은 발이, 뒤집힌 몸은 보이는 윗줄이 그대로 (맥 무대의 기준점과 같음)
                let height = rect.height * breath
                rect = CGRect(x: rect.minX, y: pet.upsideDown ? rect.minY + rect.height * shown * (1 - breath) : rect.minY,
                              width: rect.width, height: height)
            } else if breath != 1 {
                rect = rect.insetBy(dx: 0, dy: rect.height * (1 - breath) / 2)
            }
            add(OverlaySprite(image: pet.frame.texture.image, box: box(rect), mirrored: pet.frame.mirrored, flipped: pet.upsideDown,
                              visibleShare: pet.rotation == 0 ? shown : 1, alpha: pet.alpha, rotation: pet.rotation), as: "pets")
        }

        /// 머리 위 모자. 숨쉬기로 몸이 줄면 같이 내려오고, 창 윗변 뒤로 숨은 부분은 잘림
        mutating func hat(_ pet: PetDrawing<WinSprite>) {
            guard let (kind, frame) = pet.hat, pet.shownShare > 0 else { return }
            let drop = (1 - Self.breath(pet)) * pet.bodyHeight * (frame.flipY ? -1 : 1)
            let rect = frame.rect.offsetBy(dx: 0, dy: -drop)
            let shown = pet.hiddenAbove.map { min(max(($0 - rect.minY) / rect.height, 0), 1) } ?? 1
            guard shown > 0 else { return }
            add(decoration(stage.art.image(for: kind), in: rect, on: pet, mirrored: frame.flipX, flipped: frame.flipY, shown: shown), as: "hats")
        }

        /// 앞손에 든 물건 (Lv.4)
        mutating func held(_ pet: PetDrawing<WinSprite>) {
            guard let (kind, rect) = pet.held else { return }
            add(decoration(stage.art.image(for: kind), in: rect, on: pet, flipped: pet.upsideDown), as: "held")
        }

        /// 펫에 붙은 장식: 몸이 돌면 같이 돌고, 아니면 사각형 그대로
        private func decoration(_ image: PremultipliedImage, in rect: CGRect, on pet: PetDrawing<WinSprite>,
                                mirrored: Bool = false, flipped: Bool = false, shown: CGFloat = 1) -> OverlaySprite {
            guard pet.rotation != 0 else {
                return OverlaySprite(image: image, box: box(rect), mirrored: mirrored, flipped: flipped, visibleShare: shown, alpha: pet.alpha)
            }
            let center = Self.turned(CGPoint(x: rect.midX, y: rect.midY), with: pet)
            return OverlaySprite(image: image, box: box(CGRect(x: center.x - rect.width / 2, y: center.y - rect.height / 2,
                                                                width: rect.width, height: rect.height)),
                                 mirrored: mirrored, flipped: flipped, alpha: pet.alpha, rotation: pet.rotation)
        }

        /// 떨어진 물건. 드문 물건과 클릭한 물건은 뒤에 반짝임
        mutating func item(_ item: ItemDrawing) {
            if item.sparkle > 0 {
                let glint = item.rect.insetBy(dx: -item.rect.width * 0.4, dy: -item.rect.height * 0.4)
                add(OverlaySprite(image: stage.art.burst, box: box(glint), alpha: item.sparkle * item.alpha), as: "glints")
            }
            add(OverlaySprite(image: stage.art.image(for: item.kind), box: box(item.rect), alpha: item.alpha), as: "items")
        }

        /// 날아가는 무기는 돌며 날고, 닿으면 반짝임(빗나가면 회색 먼지)이 커지며 사라짐
        mutating func projectile(_ projectile: ProjectileDrawing) {
            let side = 8 * projectile.scale
            if let burst = projectile.burst {
                let grown = side * (1 + CGFloat(burst))
                add(OverlaySprite(image: projectile.missed ? stage.art.dust : stage.art.burst,
                                  box: box(CGRect(x: projectile.center.x - grown / 2, y: projectile.center.y - grown / 2, width: grown, height: grown)),
                                  alpha: 1 - CGFloat(burst)), as: projectile.missed ? "dust" : "bursts")
            } else {
                add(OverlaySprite(image: stage.art.image(for: projectile.kind),
                                  box: box(CGRect(x: projectile.center.x - side / 2, y: projectile.center.y - side / 2, width: side, height: side)),
                                  rotation: -projectile.rotation), as: "weapons")
            }
        }

        mutating func sparks(_ sparks: [EffectSpark]) {
            for spark in sparks {
                let image: PremultipliedImage
                switch spark.look {
                case .burst(let tier): image = stage.art.footstep(tier: tier)
                case .dot(let rgb): image = stage.art.dot(rgb: rgb)
                }
                let rect = CGRect(x: spark.center.x - spark.side / 2, y: spark.center.y - spark.side / 2, width: spark.side, height: spark.side)
                add(OverlaySprite(image: image, box: box(rect), alpha: spark.alpha), as: "sparks")
            }
        }

        /// 머리 위 말풍선. 그림은 DirectWrite가 화면 픽셀 그대로 그렸으므로 늘리지 않고 붙임
        mutating func bubble(_ pet: PetDrawing<WinSprite>, within bounds: ClosedRange<CGFloat>) {
            guard let speech = pet.speech, let size = stage.bubbles.bodySize(for: speech) else { return }
            let anchor = CGPoint(x: (pet.speechAnchor.x * unit).rounded() / unit, y: (pet.speechAnchor.y * unit).rounded() / unit)
            let placed = SpeechBubbleLayout.place(body: size, pointingAt: anchor, within: bounds)
            guard let picture = stage.bubbles.picture(for: speech, body: size, tailX: placed.tailX, scale: unit) else { return }
            // 그림 왼쪽 위 = 몸통 왼쪽 위에서 1포인트 바깥
            let corner = box(CGRect(x: placed.body.minX - 1, y: placed.body.maxY + 1, width: 0, height: 0))
            add(OverlaySprite(image: picture, box: PixelBox(x: corner.x, y: corner.y, width: picture.width, height: picture.height)), as: "bubbles")
        }
    }
}
