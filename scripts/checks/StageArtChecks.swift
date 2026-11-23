import Foundation

/// This object is responsible for checking the shared pieces a software stage (Windows) draws decorations with:
/// dot pictures from text grids and their tinting, rotated drawing, speech bubble geometry, and the
/// footstep and skill-trail particles.
enum StageArtChecks {
    static func run(_ check: Checker) {
        check.section("장식 그리기 (공통)")
        let red: [UInt8] = [0, 0, 255, 255], green: [UInt8] = [0, 255, 0, 255], blue: [UInt8] = [255, 0, 0, 255]
        let clear: [UInt8] = [0, 0, 0, 0]

        let dots = PremultipliedImage(rows: ["r.", ".g"], palette: ["r": 0xFF0000, "g": 0x00FF00])
        check.expect(dots.width == 2 && dots.height == 2 && Array(dots.bgra[0..<4]) == red && Array(dots.bgra[4..<8]) == clear
                     && Array(dots.bgra[12..<16]) == green, "글자 격자 → 도트 그림 (팔레트에 없는 글자는 투명)")
        let dust = PremultipliedImage(rows: ["w."], palette: ["w": 0xFFFFFF]).tinted(SceneArt.dustColor, by: 0.9)
        check.expect(Array(dust.bgra[0..<4]) == [168, 168, 168, 255] && Array(dust.bgra[4..<8]) == clear,
                     "물들이기는 색만 섞고 알파·투명 칸은 그대로", "\(Array(dust.bgra[0..<4]))")
        let cache = DotImageCache()
        check.expect(cache.image(for: ProjectileKind.club).width > 0 && cache.burst.width == 8 && cache.footstep(tier: 2).bgra != cache.burst.bgra
                     && cache.footstep(tier: 0).bgra == cache.burst.bgra, "무기·반짝임 그림과 발자국 색 단계")

        // 2x2 그림: 왼쪽 위 빨강, 오른쪽 위 초록, 왼쪽 아래 파랑, 오른쪽 아래 투명
        let image = PremultipliedImage(width: 2, height: 2, bgra: red + green + blue + clear)
        let turned = PixelCanvas(width: 4, height: 4)
        let area = turned.draw(image, center: CGPoint(x: 2, y: 2), size: CGSize(width: 4, height: 4), rotation: .pi / 2)
        check.expect(pixel(turned, 0, 0) == green && pixel(turned, 0, 3) == red && pixel(turned, 3, 3) == blue && pixel(turned, 3, 0) == clear,
                     "90도 돌리기는 화면에서 반시계 (맥 zRotation과 같은 방향)")
        check.expect(area == turned.bounds && turned.takeDirty() == area, "돌려 그린 영역도 바뀐 영역", "\(area)")
        let straight = PixelCanvas(width: 4, height: 4), boxed = PixelCanvas(width: 4, height: 4)
        straight.draw(image, center: CGPoint(x: 2, y: 2), size: CGSize(width: 4, height: 4), rotation: 0, mirrored: true)
        boxed.draw(image, in: boxed.bounds, mirrored: true)
        check.expect(straight.bgra == boxed.bgra, "돌지 않으면 사각형 그리기와 같음")

        let body = SpeechBubbleLayout.bodySize(text: CGSize(width: 20, height: 18))
        check.expect(body == CGSize(width: 38, height: 28) && SpeechBubbleLayout.bodySize(text: CGSize(width: 4, height: 18)).width == 26,
                     "말풍선 몸통은 글자에 여백, 최소 너비 26")
        let middle = SpeechBubbleLayout.place(body: body, pointingAt: CGPoint(x: 500, y: 300), within: 0...1000)
        check.expect(middle.body == CGRect(x: 481, y: 306, width: 38, height: 28) && middle.tailX == 19,
                     "말풍선은 머리 위 가운데, 꼬리 끝은 펫을 가리킴", "\(middle)")
        let edge = SpeechBubbleLayout.place(body: body, pointingAt: CGPoint(x: 5, y: 300), within: 0...1000)
        check.expect(edge.body.minX == 2 && edge.tailX == 10, "화면 가장자리에서는 몸통이 안쪽에 남고 꼬리만 옮겨 감", "\(edge)")
        check.expect(SpeechBubbleStyle(.notice).fontSize < SpeechBubbleStyle(.chatter).fontSize, "일정 안내는 조금 작은 글자")

        let effects = SceneEffects(random: { 0.25 })
        let walker = drawing(id: "walker", foot: CGPoint(x: 100, y: 50), sparkles: true)
        effects.step(Scene(pets: [walker], projectiles: [], items: []))
        let step = effects.sparks
        check.expect(step.count == 1 && step[0].center == CGPoint(x: 98, y: 52) && step[0].look == .burst(tier: 0) && !step[0].front
                     && abs(step[0].alpha - 0.55) < 0.001, "Lv.5 걸음은 발밑에 옅은 반짝임 (펫 뒤)", "\(step)")
        for _ in 0..<8 { effects.step(Scene(pets: [walker], projectiles: [], items: []) as Scene<String>) }
        check.expect(effects.sparks.count == 1, "발자국은 0.15초 간격")
        for _ in 0..<40 { effects.step(Scene<String>(pets: [], projectiles: [], items: [])) }
        check.expect(effects.sparks.isEmpty, "0.6초 뒤 사라짐")

        let leaper = drawing(id: "leaper", foot: CGPoint(x: 300, y: 80), trail: .flameRocket)
        effects.step(Scene(pets: [leaper], projectiles: [], items: []))
        let flame = effects.sparks
        check.expect(flame.count == 2 && flame.allSatisfy { $0.look == .dot(rgb: 0xFFF280) && $0.center == CGPoint(x: 300, y: 82) },
                     "불꽃 도약은 발에서 1/60초에 2~3개, 처음 색은 밝은 노랑", "\(flame.count)")
        for _ in 0..<12 { effects.step(Scene<String>(pets: [], projectiles: [], items: [])) }
        let later = effects.sparks.first
        check.expect(later.map { $0.look != .dot(rgb: 0xFFF280) && $0.center.y < 80 && $0.side < 8 * 0.9 } ?? false,
                     "입자는 뿜은 자리에서 아래로 날며 작아지고 색이 바뀜", "\(String(describing: later))")
    }

    private static func drawing(id: String, foot: CGPoint, sparkles: Bool = false, trail: SkillStyle? = nil) -> PetDrawing<String> {
        var drawing = PetDrawing(id: id, frame: SpriteFrame(texture: id, mirrored: false),
                                 rect: CGRect(x: foot.x - 36, y: foot.y, width: 72, height: 72), breathPhase: nil, speech: nil,
                                 trail: trail, foot: foot, bodyHeight: 40, speechAnchor: CGPoint(x: foot.x, y: foot.y + 44))
        drawing.sparkles = sparkles
        return drawing
    }

    private static func pixel(_ canvas: PixelCanvas, _ x: Int, _ y: Int) -> [UInt8] {
        let start = (y * canvas.width + x) * 4
        return Array(canvas.bgra[start..<(start + 4)])
    }
}
