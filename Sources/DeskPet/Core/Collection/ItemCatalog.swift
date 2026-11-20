import Foundation

/// 물건 희귀도 (드문 물건은 반짝임과 🌟)
enum ItemRarity: Equatable {
    case common
    case rare
}

/// 물건 한 종류: 이름, 8×8 도트 그림, 나오는 비중 (그림은 무대가 텍스처로 바꿈)
struct ItemKind: Equatable {
    let id: String
    let englishName: String
    let koreanName: String
    /// 위에서 아래 줄 순서의 도트. "."은 투명, 나머지 글자는 palette 키
    let rows: [String]
    let palette: [Character: UInt32]
    let rarity: ItemRarity
    /// 나오는 비중 (늘 나오는 물건 합 100 기준)
    let weight: Double
    /// 나오는 달 (nil이면 일 년 내내). 계절 물건만
    var months: Set<Int>? = nil

    /// 그 달에 나오는지
    func isAvailable(inMonth month: Int) -> Bool {
        months.map { $0.contains(month) } ?? true
    }

    func name(in language: MenuLanguage) -> String {
        language == .korean ? koreanName : englishName
    }

    static func == (lhs: ItemKind, rhs: ItemKind) -> Bool { lhs.id == rhs.id }
}

/// This object is responsible for the list of items pets can find: their names, pixel art, how often each appears
/// and, for seasonal ones, the months they turn up in. Data only; changing a weight here changes the drop odds directly.
enum ItemCatalog {
    static let all: [ItemKind] = [
        ItemKind(id: "acorn", englishName: "Acorn", koreanName: "도토리",
                 rows: ["...kk...", ".kcccck.", "kcccccck", "kknnnnkk", ".knlnnk.", ".knnnnk.", "..knnk..", "...kk..."],
                 palette: ["k": 0x3B2414, "c": 0x7A4A22, "n": 0xB8743A, "l": 0xE8B070], rarity: .common, weight: 18),
        ItemKind(id: "shell", englishName: "Shell", koreanName: "조개",
                 rows: ["..kkkk..", ".kpwpwk.", "kpwpwpwk", "kpwpwpwk", "kpwpwpwk", ".kpwpwk.", "..kkkk..", "...kk..."],
                 palette: ["k": 0x8A3A55, "p": 0xF2A0B8, "w": 0xFFE0EA], rarity: .common, weight: 16),
        ItemKind(id: "feather", englishName: "Feather", koreanName: "깃털",
                 rows: ["......kk", ".....kwk", "....kwbk", "...kwbk.", "..kwbk..", ".kwbk...", ".kk.....", "k......."],
                 palette: ["k": 0x4A6A8A, "w": 0xFFFFFF, "b": 0xA8D8F0], rarity: .common, weight: 16),
        ItemKind(id: "button", englishName: "Button", koreanName: "단추",
                 rows: ["..kkkk..", ".krrrrk.", "krdrrdrk", "krrrrrrk", "krrrrrrk", "krdrrdrk", ".krrrrk.", "..kkkk.."],
                 palette: ["k": 0x6A1010, "r": 0xD83030, "d": 0x801818], rarity: .common, weight: 15),
        ItemKind(id: "clover", englishName: "Clover", koreanName: "네잎클로버",
                 rows: [".kk.kk..", "kglkglk.", "kggkggk.", ".kkgkk..", "kglkglk.", "kggkggk.", ".kk.kkk.", "......kk"],
                 palette: ["k": 0x1E5A1E, "g": 0x3CB043, "l": 0x8EE08E], rarity: .common, weight: 14),
        ItemKind(id: "candy", englishName: "Candy", koreanName: "사탕",
                 rows: ["........", "kk....kk", "krkkkkrk", ".kwrwrk.", ".krwrwk.", "krkkkkrk", "kk....kk", "........"],
                 palette: ["k": 0x7A1F4A, "w": 0xFFFFFF, "r": 0xE83A6A], rarity: .common, weight: 13),
        ItemKind(id: "star_shard", englishName: "Star Shard", koreanName: "별 조각",
                 rows: ["...k....", "..kyk...", "kkyyykk.", "kyywyyk.", ".kyyyk..", ".kykyk..", "kyk.kyk.", "kk...kk."],
                 palette: ["k": 0x8A6A00, "y": 0xFFD23F, "w": 0xFFF6D0], rarity: .rare, weight: 2.5),
        ItemKind(id: "crown_piece", englishName: "Crown Piece", koreanName: "왕관 조각",
                 rows: ["........", "k..kk..k", "kgkggkgk", "kggggggk", "kglgrglk", "kggggggk", "kkkkkkkk", "........"],
                 palette: ["k": 0x7A5A10, "g": 0xF0C030, "l": 0xFFF0A0, "r": 0xD83030], rarity: .rare, weight: 2),
        ItemKind(id: "rainbow_marble", englishName: "Rainbow Marble", koreanName: "무지개 구슬",
                 rows: ["..kkkk..", ".krrwok.", "krrooyyk", "kooyyggk", "kyygggbk", "kygggbbk", ".kgbbbk.", "..kkkk.."],
                 palette: ["k": 0x404060, "r": 0xE83A3A, "o": 0xF09030, "y": 0xF0E040, "g": 0x40C060, "b": 0x4080F0, "w": 0xFFFFFF],
                 rarity: .rare, weight: 2),
        ItemKind(id: "golden_key", englishName: "Golden Key", koreanName: "황금 열쇠",
                 rows: [".kkk....", "klggk...", "kg.gk...", ".kggkkkk", "..kggggk", "....kgkk", "....kk..", "........"],
                 palette: ["k": 0x7A5A10, "g": 0xF0C030, "l": 0xFFF0A0], rarity: .rare, weight: 1.5),
        // 계절 물건 (북반구 기준, 그 달에만 나옴)
        ItemKind(id: "snowflake", englishName: "Snowflake", koreanName: "눈송이",
                 rows: ["...k....", ".k.w.k..", "..kwk...", "kwwbwwk.", "..kwk...", ".k.w.k..", "...k....", "........"],
                 palette: ["k": 0x4A7AA8, "w": 0xFFFFFF, "b": 0xA8D8F0], rarity: .common, weight: 6, months: [12, 1, 2]),
        ItemKind(id: "blossom", englishName: "Blossom", koreanName: "벚꽃",
                 rows: ["..kkk...", ".kpppk..", "kkpwpkk.", "kppyppk.", "kkpwpkk.", ".kpppk..", "..kkk...", "........"],
                 palette: ["k": 0xB04A78, "p": 0xF5A0C0, "w": 0xFFE0EC, "y": 0xF0D040], rarity: .common, weight: 6, months: [3, 4]),
    ]

    static func item(_ id: String) -> ItemKind? {
        all.first { $0.id == id }
    }

    /// 그 달에 나오는 물건 중 비중대로 하나 고름. roll은 0 이상 1 미만의 난수
    static func pick(roll: Double, month: Int) -> ItemKind {
        let pool = all.filter { $0.isAvailable(inMonth: month) }
        let total = pool.reduce(0) { $0 + $1.weight }
        var roll = roll * total
        for item in pool {
            roll -= item.weight
            if roll < 0 { return item }
        }
        return pool[pool.count - 1]
    }

    /// 계절 물건의 기간 이름 (예: 12~2월). 늘 나오면 nil
    static func seasonLabel(of item: ItemKind, in language: MenuLanguage) -> String? {
        guard let months = item.months, !months.isEmpty else { return nil }
        // 해를 넘는 기간(12~2월)도 이어서 읽도록 빈 달 다음부터 셈
        let start = (1...12).first { months.contains($0) && !months.contains($0 == 1 ? 12 : $0 - 1) } ?? months.min()!
        let end = (1...12).first { months.contains($0) && !months.contains($0 == 12 ? 1 : $0 + 1) } ?? months.max()!
        if language == .korean { return "\(start)~\(end)월" }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[start - 1])–\(names[end - 1])"
    }
}
