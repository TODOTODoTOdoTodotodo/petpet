import Foundation
import WinSDK

/// This object is responsible for drawing the simulation on Windows: one layered overlay per monitor,
/// rebuilt when the monitor layout changes, and every tick the shared scene's pet drawings placed in each
/// overlay's pixels (feet, mirroring, peeking from behind a window top and transparency as Core decided).
/// Speech bubbles, hats, weapons and effects come in phase 3; taking clicks on pets in phase 2d.
final class OverlayStage: PetStage {
    private let instance = GetModuleHandleW(nil)
    private let composer = SceneComposer<WinSprite>.forSkins()
    private var areas: [ScreenArea] = []
    private var overlays: [LayeredOverlay] = []
    private var coordinates = WindowsCoordinates.current()
    private(set) var lastDrawings = 0
    /// 펫 전체 투명도 (메뉴의 Opacity)
    var opacity: CGFloat = 1

    func rebuild(for areas: [ScreenArea]) {
        guard areas != self.areas else { return }
        overlays.forEach { $0.close() }
        coordinates = WindowsCoordinates.current()
        self.areas = areas
        overlays = areas.compactMap { area in
            LayeredOverlay(box: coordinates.pixelBox(area.frame, origin: POINT(x: 0, y: 0)), instance: instance)
        }
    }

    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], discreet: Bool) {
        let drawings = composer.compose(pets, projectiles: projectiles, items: items, discreet: discreet).pets
        lastDrawings = drawings.count
        for overlay in overlays {
            let sprites = drawings.compactMap { drawing -> OverlaySprite? in
                let box = coordinates.pixelBox(drawing.rect, origin: overlay.origin)
                guard !box.intersection(overlay.canvas.bounds).isEmpty else { return nil }
                return OverlaySprite(image: drawing.frame.texture.image, box: box, mirrored: drawing.frame.mirrored,
                                     flipped: drawing.upsideDown, visibleShare: drawing.shownShare, alpha: drawing.alpha * opacity)
            }
            overlay.render(sprites)
        }
    }

    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {}

    /// 무대별 크기와 보이는 픽셀 수 (연기 시험 보고서용)
    var summary: [[String: Any]] {
        overlays.map {
            ["x": Int($0.origin.x), "y": Int($0.origin.y), "width": $0.canvas.width, "height": $0.canvas.height,
             "visiblePixels": $0.canvas.visiblePixelCount]
        }
    }

    func close() {
        overlays.forEach { $0.close() }
        overlays = []
    }
}
