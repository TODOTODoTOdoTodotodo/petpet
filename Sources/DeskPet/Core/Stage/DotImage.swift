import Foundation

extension PremultipliedImage {
    /// 글자 격자(무기·모자·물건·반짝임)에서. 팔레트에 없는 글자는 투명, 있는 글자는 불투명
    init(rows: [String], palette: [Character: UInt32]) {
        let width = rows.map(\.count).max() ?? 0
        var bgra = [UInt8](repeating: 0, count: width * rows.count * 4)
        for (y, row) in rows.enumerated() {
            for (x, symbol) in row.enumerated() {
                guard let color = palette[symbol] else { continue }
                let index = (y * width + x) * 4
                bgra[index] = UInt8(color & 0xFF)
                bgra[index + 1] = UInt8((color >> 8) & 0xFF)
                bgra[index + 2] = UInt8((color >> 16) & 0xFF)
                bgra[index + 3] = 255
            }
        }
        self.init(width: width, height: rows.count, bgra: bgra)
    }

    /// 색을 factor(0~1)만큼 rgb 쪽으로 섞은 그림 (맥 SpriteKit의 colorBlendFactor와 같은 셈). 알파는 그대로
    func tinted(_ rgb: UInt32, by factor: CGFloat) -> PremultipliedImage {
        let share = min(max(factor, 0), 1)
        guard share > 0 else { return self }
        let tint = [CGFloat(rgb & 0xFF), CGFloat((rgb >> 8) & 0xFF), CGFloat((rgb >> 16) & 0xFF)]
        var mixed = bgra
        for index in stride(from: 0, to: mixed.count, by: 4) {
            let alpha = CGFloat(bgra[index + 3])
            guard alpha > 0 else { continue }
            for channel in 0..<3 {
                // 미리 곱한 값이라 물들일 색에도 알파를 곱함
                let original = CGFloat(bgra[index + channel])
                mixed[index + channel] = UInt8((original * (1 - share) + tint[channel] * alpha / 255 * share).rounded())
            }
        }
        return PremultipliedImage(width: width, height: height, bgra: mixed)
    }
}

/// This object is responsible for the dot pictures a software stage draws besides skins (weapons, hats, items,
/// the burst sparkle and the round particle), built once per name from their shared text grids and kept.
final class DotImageCache {
    private var images: [String: PremultipliedImage] = [:]

    func image(for kind: ProjectileKind) -> PremultipliedImage {
        cached("weapon." + kind.name) { PremultipliedImage(rows: kind.rows, palette: kind.palette) }
    }

    func image(for hat: HatKind) -> PremultipliedImage {
        cached("hat." + hat.id) { PremultipliedImage(rows: hat.rows, palette: hat.palette) }
    }

    func image(for item: ItemKind) -> PremultipliedImage {
        cached("item." + item.id) { PremultipliedImage(rows: item.rows, palette: item.palette) }
    }

    var burst: PremultipliedImage {
        cached("burst") { PremultipliedImage(rows: ProjectileKind.burstRows, palette: ProjectileKind.burstPalette) }
    }

    /// 빗나간 무기의 먼지 (반짝임을 회색으로)
    var dust: PremultipliedImage {
        cached("dust") { burst.tinted(SceneArt.dustColor, by: 0.9) }
    }

    /// 발자국 색 단계별 반짝임 (0단계는 원래 노란색)
    func footstep(tier: Int) -> PremultipliedImage {
        guard tier > 0, tier < SceneArt.footstepTints.count, let tint = SceneArt.footstepTints[tier] else { return burst }
        return cached("footstep.\(tier)") { burst.tinted(tint, by: 0.75) }
    }

    /// 꼬리 입자용 흰 원 (8×8). 색은 그릴 때 물들임
    var dot: PremultipliedImage {
        cached("dot") {
            PremultipliedImage(rows: ["..####..", ".######.", "########", "########", "########", "########", ".######.", "..####.."],
                               palette: ["#": 0xFFFFFF])
        }
    }

    /// 색을 입힌 둥근 입자. 불꽃처럼 색이 계속 바뀌므로 채널마다 16단계로 묶어 보관
    func dot(rgb: UInt32) -> PremultipliedImage {
        let stepped = rgb & 0xF0F0F0 | (rgb & 0xF0F0F0) >> 4
        return cached("dot.\(stepped)") { dot.tinted(stepped, by: 1) }
    }

    private func cached(_ name: String, _ make: () -> PremultipliedImage) -> PremultipliedImage {
        if let image = images[name] { return image }
        let image = make()
        images[name] = image
        return image
    }
}

/// 맥 무대와 같은 장식 색 (윈도우 무대가 씀)
enum SceneArt {
    /// 빗나간 무기가 닿은 자리의 먼지 색
    static let dustColor: UInt32 = 0x9E9E9E
    /// 발자국 색 단계별 물들임 (0단계는 원래 노란색)
    static let footstepTints: [UInt32?] = [nil, 0xFF8CC7, 0xFFCC33]
}
