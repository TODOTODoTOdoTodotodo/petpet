import Foundation

/// 한 틱에 그릴 모든 것 (전역 좌표). Frame은 플랫폼 텍스처
struct Scene<Frame> {
    let pets: [PetDrawing<Frame>]
    let projectiles: [ProjectileDrawing]
    let items: [ItemDrawing]
}

/// This object is responsible for turning the simulation into what to draw this tick, the same way on every platform:
/// placing each pet's sprite so its feet touch the ledge and its body is centered on its position (also when mirrored
/// or upside down), hiding speech while nearly invisible or during calls, and deciding hats, held items and sparkles.
/// The platform stage only puts the resulting drawings on its screens.
final class SceneComposer<Frame> {
    /// 반짝 발자국이 생기는 친밀도 레벨
    static var sparkleLevel: Int { 5 }

    private let frames: (Pet) -> SpriteFrame<Frame>?
    /// 반짝임 위상용 시계
    private var clock: TimeInterval = 0

    /// frames: 펫의 지금 동작·방향·시간에 맞는 프레임 (없으면 그 펫은 그리지 않음)
    init(frames: @escaping (Pet) -> SpriteFrame<Frame>?) {
        self.frames = frames
    }

    /// 스킨(`PetSkin<Frame>`)을 입은 펫을 그리는 기본 구성
    static func forSkins() -> SceneComposer<Frame> {
        SceneComposer { pet in
            (pet.appearance as? PetSkin<Frame>)?.sprite(for: pet.animation, facing: pet.displayFacing, elapsed: pet.animationElapsed)
        }
    }

    /// notes: 구겨 던진 알림 더미 (물건처럼 그림). discreet: 통화 중이라 일정 제목을 숨기고 말풍선을 키우지 않을지.
    /// 한 번 부를 때마다 1/60초가 흐른 것으로 봄
    func compose(_ pets: [Pet], projectiles: [Projectile] = [], items: [DroppedItem] = [], notes: [CrumpledNotice] = [],
                 discreet: Bool = false) -> Scene<Frame> {
        clock += 1.0 / 60
        return Scene(
            pets: pets.compactMap { drawing(of: $0, discreet: discreet) },
            projectiles: projectiles.map(ProjectileDrawing.init),
            items: items.filter(\.isOnScreen).map { ItemDrawing($0, clock: clock) } + notes.map(ItemDrawing.init)
        )
    }

    private func drawing(of pet: Pet, discreet: Bool) -> PetDrawing<Frame>? {
        guard let frame = frames(pet) else { return nil }
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
