import AppKit
import SpriteKit

/// This object is responsible for keeping one SpriteKit stage per display in step with the screen layout,
/// handing every stage the shared scene drawings, and letting only the stage under a grabbable pet take clicks.
final class StageDirector: PetStage {
    private(set) var stages: [ScreenStage] = []
    /// 그릴 목록 계산 (발 맞춤·반전 보정·모자·발자국은 공통 코드)
    private let composer = SceneComposer<SKTexture>.forSkins()
    var opacity: CGFloat = 1 {
        didSet { stages.forEach { $0.setOpacity(opacity) } }
    }

    /// 모니터 구성이 바뀌면 무대를 새로 만듦 (펫은 PetRoster에 그대로 남음)
    func rebuild(for areas: [ScreenArea]) {
        guard areas != stages.map(\.area) else { return }
        stages.forEach { $0.close() }
        stages = areas.map(ScreenStage.init(area:))
        stages.forEach { $0.setOpacity(opacity) }
    }

    /// discreet: 통화 중이라 일정 제목을 숨길지
    func render(_ pets: [Pet], projectiles: [Projectile] = [], items: [DroppedItem] = [], discreet: Bool = false) {
        let scene = composer.compose(pets, projectiles: projectiles, items: items, discreet: discreet)
        stages.forEach { $0.render(scene.pets, projectiles: scene.projectiles, items: scene.items) }
    }

    /// 커서가 있는 무대만, 펫이나 물건을 잡을 수 있을 때 마우스를 받음
    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {
        for stage in stages {
            stage.catchesMouse = wantsMouse && stage.area.frame.contains(cursor)
        }
    }

    func bringToFront() {
        stages.forEach { $0.bringToFront() }
    }
}
