import Foundation

/// This object is responsible for checking the shared scene composition every platform stage draws from:
/// foot and center alignment of sprites (also mirrored), skipped pets without frames, speech hiding and items.
enum SceneChecks {
    static func run(_ check: Checker) {
        check.section("그리기 목록 (공통)")
        // 발 아래 투명 여백 3, 몸 중심 x=20 (칸 가운데 24보다 왼쪽)
        let look = OffsetAppearance(body: BodyMetrics(footInset: 3, width: 20, height: 30, centerX: 20))
        let pet = Sim.pet(at: CGPoint(x: 500, y: 200), appearance: look, behavior: IdleBehavior(duration: 999))
        var mirrored = false
        let composer = SceneComposer<String> { pet in
            pet.appearance is OffsetAppearance ? SpriteFrame(texture: pet.id, mirrored: mirrored) : nil
        }

        let drawing = composer.compose([pet]).pets.first
        let side = Pet.frameSide * 1.5
        check.expect(drawing?.rect == CGRect(x: 500 - side / 2 + 6, y: 200 - 4.5, width: side, height: side),
                     "발 여백만큼 내리고 몸 중심을 발 위치에 맞춤", "\(String(describing: drawing?.rect))")
        mirrored = true
        check.expect(composer.compose([pet]).pets.first?.rect.minX == 500 - side / 2 - 6, "반전되면 중심 보정도 반대로")
        check.expect(composer.compose([pet]).pets.first?.frame.texture == "Check", "플랫폼 프레임을 그대로 실음")

        let plain = Sim.pet(at: CGPoint(x: 800, y: 200), behavior: IdleBehavior(duration: 999))
        check.expect(composer.compose([pet, plain]).pets.count == 1, "프레임이 없는 펫은 건너뜀")

        pet.say("hello")
        check.expect(composer.compose([pet]).pets.first?.speech?.text == "hello", "말풍선을 실음")
        check.expect(composer.compose([pet], discreet: true).pets.first?.speech == pet.speech?.discreet,
                     "통화 중에는 조심스러운 말풍선")

        let world = Sim.world()
        let item = DroppedItem(id: "item-1", kind: ItemCatalog.all[0], scale: 1.5, position: CGPoint(x: 300, y: 600))
        item.step(dt: Sim.dt, in: world)
        check.expect(item.isOnScreen && composer.compose([], items: [item]).items.map(\.id) == ["item-1"], "화면에 있는 물건을 그림")
    }
}

/// This object is responsible for a pet look with a chosen body box, for alignment checks.
final class OffsetAppearance: PetAppearance {
    let name = "Offset"
    let body: BodyMetrics
    let skillStyle: SkillStyle = .bigJump

    init(body: BodyMetrics) {
        self.body = body
    }

    func supports(_ kind: AnimationKind) -> Bool { true }

    func cycleDuration(of kind: AnimationKind, facing: Facing) -> TimeInterval { 0 }
}
