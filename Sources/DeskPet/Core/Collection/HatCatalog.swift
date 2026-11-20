import Foundation

/// 모자를 얻는 조건 (모은 누적 개수만 봄, 물건은 줄지 않음)
enum HatCondition: Equatable {
    /// 아무 물건 합계
    case total(Int)
    /// 그 물건 개수
    case item(String, Int)

    var need: Int {
        switch self {
        case .total(let count), .item(_, let count): return count
        }
    }
}

/// 모자 한 종류: 이름, 도트 그림(왼쪽을 보는 모습), 얻는 조건
struct HatKind: Equatable {
    let id: String
    let englishName: String
    let koreanName: String
    /// 위에서 아래 줄 순서의 도트. 왼쪽(west)을 볼 때 모습. "."은 투명
    let rows: [String]
    let palette: [Character: UInt32]
    let condition: HatCondition

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    func name(in language: MenuLanguage) -> String {
        language == .korean ? koreanName : englishName
    }

    static func == (lhs: HatKind, rhs: HatKind) -> Bool { lhs.id == rhs.id }
}

/// This object is responsible for the hats pets can earn: their pixel art and the collection count that unlocks each.
/// Data only; the order here is the order shown in menus.
enum HatCatalog {
    static let all: [HatKind] = [
        HatKind(id: "leaf_cap", englishName: "Leaf Cap", koreanName: "나뭇잎 모자",
                rows: ["......kk..", "...kkkgk..", "..kgggggk.", ".kglggggk.", "kggggggggk", "kkkkkkkkkk"],
                palette: ["k": 0x1E5A1E, "g": 0x48B048, "l": 0x9AE09A], condition: .total(10)),
        HatKind(id: "acorn_cap", englishName: "Acorn Cap", koreanName: "도토리 모자",
                rows: [".....kk...", "..kkkckk..", ".kcdcdcdk.", "kcdcdcdcdk", "kddddddddk", "kkkkkkkkkk"],
                palette: ["k": 0x3B2414, "c": 0x8A5A2A, "d": 0x6A4018], condition: .item("acorn", 5)),
        HatKind(id: "feather_band", englishName: "Feather Band", koreanName: "깃털 머리띠",
                rows: ["..........kk", ".........kwk", "........kwbk", ".......kwbk.", "......kwbk..", "kkkkkkkkkkkk", "rrrrrrrrrrrr"],
                palette: ["k": 0x3A2A4A, "w": 0xFFFFFF, "b": 0xA8D8F0, "r": 0xC83A3A], condition: .item("feather", 5)),
        HatKind(id: "bow", englishName: "Bow", koreanName: "리본",
                rows: ["kk......kk", "krk....krk", "krrkkkkrrk", "krk.kk.krk", "kk......kk"],
                palette: ["k": 0x6A1010, "r": 0xE04050], condition: .item("button", 5)),
        HatKind(id: "flower_crown", englishName: "Flower Crown", koreanName: "꽃 화관",
                rows: [".p...y...p..", "pwp.ywy.pwp.", ".p.g.y.g.p.g", "gggggggggggg", "kkkkkkkkkkkk"],
                palette: ["p": 0xF080B0, "y": 0xF0D040, "w": 0xFFFFFF, "g": 0x48B048, "k": 0x1E5A1E], condition: .item("clover", 5)),
        HatKind(id: "candy_pin", englishName: "Candy Pin", koreanName: "사탕 핀",
                rows: [".kkkk.", "kwrwrk", "krwrwk", "kwrwrk", ".kkkk.", "..k..."],
                palette: ["k": 0x7A1F4A, "w": 0xFFFFFF, "r": 0xE83A6A], condition: .item("candy", 5)),
        HatKind(id: "star_hat", englishName: "Star Hat", koreanName: "별 모자",
                rows: [".....k....", "....kbk...", "...kbbk...", "...kbyk...", "..kbyyyk..", "..kbbybk..", ".kbbbbbbk.", "kbbbbbbbbk", "kkkkkkkkkk"],
                palette: ["k": 0x1A1A40, "b": 0x3A3AA0, "y": 0xFFD23F], condition: .item("star_shard", 1)),
        HatKind(id: "crown", englishName: "Crown", koreanName: "왕관",
                rows: ["k....kk....k", "kk..kggk..kk", "kgk.kggk.kgk", "kggkggggkggk", "kgggrggrgggk", "kggggggggggk", "kkkkkkkkkkkk"],
                palette: ["k": 0x7A5A10, "g": 0xF0C030, "r": 0xD83030], condition: .item("crown_piece", 3)),
    ]

    static func hat(_ id: String) -> HatKind? {
        all.first { $0.id == id }
    }
}

/// 그릴 모자의 자리 (전역 좌표)
struct HatFrame: Equatable {
    let rect: CGRect
    /// 오른쪽을 볼 때 좌우 반전 (그림은 왼쪽을 봄)
    let flipX: Bool
    /// 거꾸로 매달렸을 때 위아래 반전 (머리 아래에 붙음)
    let flipY: Bool
}

/// This object is responsible for where a hat sits on a pet: centered on the top of its measured body
/// (sunk a little so it rests on the head), facing the way the pet faces, under the head when the pet hangs
/// upside down, and nudged by the skin's own hatAnchor when its head is off-center.
enum HatPlacement {
    /// 머리에 얹히도록 몸 꼭대기 아래로 내리는 도트 수
    static let sink: CGFloat = 2

    static func frame(of hat: HatKind, on pet: Pet) -> HatFrame {
        let s = pet.scale
        let size = CGSize(width: CGFloat(hat.width) * s, height: CGFloat(hat.height) * s)
        let facing = pet.displayFacing
        let forward: CGFloat = facing == .east ? 1 : (facing == .west ? -1 : 0)
        let anchor = pet.appearance.hatAnchor
        let x = pet.position.x + forward * anchor.dx * s - size.width / 2
        let rise = (anchor.dy - sink) * s
        if pet.pose.upsideDown {
            let head = pet.position.y - pet.bodyHeight
            return HatFrame(rect: CGRect(x: x, y: head - rise - size.height, width: size.width, height: size.height),
                            flipX: facing == .east, flipY: true)
        }
        let head = pet.position.y + pet.bodyHeight
        return HatFrame(rect: CGRect(x: x, y: head + rise, width: size.width, height: size.height), flipX: facing == .east, flipY: false)
    }
}
