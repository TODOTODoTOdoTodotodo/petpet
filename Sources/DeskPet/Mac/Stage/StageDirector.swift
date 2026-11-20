import AppKit

/// This object is responsible for keeping one stage per display in step with the screen layout,
/// turning pets into drawings for every stage, and letting only the stage under a grabbable pet take clicks.
final class StageDirector {
    private(set) var stages: [ScreenStage] = []
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
        clock += 1.0 / 60
        let drawings = pets.compactMap { drawing(of: $0, discreet: discreet) }
        let thrown = projectiles.map(ProjectileDrawing.init)
        let found = items.filter(\.isOnScreen).map { ItemDrawing($0, clock: clock) }
        stages.forEach { $0.render(drawings, projectiles: thrown, items: found) }
    }

    /// 반짝 발자국이 생기는 친밀도 레벨
    static let sparkleLevel = 5

    /// 반짝임 위상용 시계
    private var clock: TimeInterval = 0

    /// 커서가 있는 무대만, 펫이나 물건을 잡을 수 있을 때 마우스를 받음
    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {
        for stage in stages {
            stage.catchesMouse = wantsMouse && stage.area.frame.contains(cursor)
        }
    }

    func bringToFront() {
        stages.forEach { $0.bringToFront() }
    }

    private func drawing(of pet: Pet, discreet: Bool) -> PetDrawing? {
        guard let source = pet.appearance as? SpriteSource,
              let frame = source.sprite(for: pet.animation, facing: pet.displayFacing, elapsed: pet.animationElapsed)
        else { return nil }
        let side = pet.spriteSide
        let body = pet.appearance.body
        // 스프라이트 아래 투명 여백만큼 내려 발이 발판에 닿게 하고, 몸 중심을 발 위치에 맞춤
        // 뒤집혔으면 발 높이를 축으로 뒤집은 자리 (머리가 발 아래)
        let bottom = pet.pose.upsideDown ? pet.position.y - side + body.footInset * pet.scale : pet.position.y - body.footInset * pet.scale
        let centerShift = (body.centerX - Pet.frameSide / 2) * pet.scale * (frame.mirrored ? -1 : 1)
        let left = pet.position.x - side / 2 - centerShift
        return PetDrawing(
            id: pet.id,
            frame: frame,
            rect: CGRect(x: left, y: bottom, width: side, height: side),
            breathPhase: pet.effect == .breathing ? pet.animationElapsed : nil,
            // 거의 사라진 동안은 말풍선도 숨김
            speech: pet.opacity < 0.3 ? nil : (discreet ? pet.speech?.discreet : pet.speech),
            trail: { () -> SkillStyle? in if case .trail(let style) = pet.effect { return style } else { return nil } }(),
            foot: pet.position,
            bodyHeight: pet.bodyHeight,
            speechAnchor: CGPoint(x: pet.position.x, y: (pet.visibleBodyRect ?? pet.bodyRect).maxY + 4),
            alpha: pet.opacity,
            upsideDown: pet.pose.upsideDown,
            hiddenAbove: pet.pose.hiddenAbove,
            hat: pet.hat.map { ($0, HatPlacement.frame(of: $0, on: pet)) },
            held: pet.heldItem.flatMap { item in HeldPlacement.rect(on: pet).map { (item, $0) } },
            rotation: pet.behavior.bodyRotation,
            sparkles: pet.level >= Self.sparkleLevel && pet.animation == .walk && pet.support != nil,
            sparkleTier: pet.sparkleTier
        )
    }
}
