import Foundation

/// 물건 하나를 넣은 결과
struct CollectResult: Equatable {
    /// 그 물건의 새 개수
    let count: Int
    /// 이번에 새로 얻은 모자
    let unlocked: [HatKind]
    /// 주운 펫이 모자가 없어 바로 쓴 모자
    let worn: HatKind?
}

/// This object is responsible for the user's collection: how many of each item the pets have found, the day each kind
/// was first found, which hats those counts have unlocked (and which are still new), and each pet's record: the hat it
/// wears, its affection (❤️ under daily caps, and the level that gives), its name and the item it holds.
/// It never shrinks except on an explicit reset or when a pet is removed, and it reads and writes its saved form.
final class Treasury {
    /// 저장 형식 버전 (다르면 깨진 것으로 봄). 모자·펫 기록은 1단계 저장에 없어도 읽음
    static let version = 1

    private(set) var counts: [String: Int] = [:]
    /// 물건별 처음 찾은 날 (yyyy-MM-dd, 그 맥의 날짜)
    private(set) var firstFound: [String: String] = [:]
    /// 얻은 모자 (얻은 순서)
    private(set) var hats: [String] = []
    /// 얻었지만 아직 메뉴에서 보지 않은 모자
    private(set) var newHats: Set<String> = []
    /// 펫 고유 ID → 그 펫의 기록 (모자·친밀도·이름·소품)
    private var logs: [String: PetLog] = [:]
    /// 펫 고유 ID → 쓰고 있는 모자
    var wearing: [String: String] { logs.compactMapValues(\.hat) }
    /// 저장하지 않은 ❤️ 변화가 있는지
    private(set) var hasUnsavedHearts = false

    /// 레벨 경계 (Lv.1~6의 누적 ❤️)
    static let levelThresholds = [0, 10, 30, 60, 100, 150]
    /// 이름 최대 글자 수
    static let maxNameLength = 12
    /// 손 소품을 들 수 있는 레벨, 이름을 지을 수 있는 레벨
    static let holdLevel = 4
    static let nameLevel = 6

    /// 펫 하나의 기록
    private struct PetLog: Codable, Equatable {
        var hat: String?
        var hearts = 0
        var held: String?
        var name: String?
        var today: DayTally?

        init() {}

        /// 이전 단계 저장(모자만 있음)도 읽도록 없는 키는 기본값
        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            hat = try box.decodeIfPresent(String.self, forKey: .hat)
            hearts = try box.decodeIfPresent(Int.self, forKey: .hearts) ?? 0
            held = try box.decodeIfPresent(String.self, forKey: .held)
            name = try box.decodeIfPresent(String.self, forKey: .name)
            today = try box.decodeIfPresent(DayTally.self, forKey: .today)
        }
    }

    /// 하루 동안 갈래별로 받은 ❤️ (자정이 지나면 새로)
    private struct DayTally: Codable, Equatable {
        var date: String
        var given: [String: Int] = [:]

        init(date: String) {
            self.date = date
        }

        init(from decoder: Decoder) throws {
            let box = try decoder.container(keyedBy: CodingKeys.self)
            date = try box.decode(String.self, forKey: .date)
            given = try box.decodeIfPresent([String: Int].self, forKey: .given) ?? [:]
        }
    }

    var total: Int { counts.values.reduce(0, +) }

    func count(of item: ItemKind) -> Int {
        counts[item.id] ?? 0
    }

    func hasFound(_ item: ItemKind) -> Bool {
        count(of: item) > 0
    }

    func isUnlocked(_ hat: HatKind) -> Bool {
        hats.contains(hat.id)
    }

    /// 조건까지 모은 수 (넘쳐도 조건 수까지만)
    func progress(toward hat: HatKind) -> Int {
        switch hat.condition {
        case .total(let need): return min(total, need)
        case .item(let id, let need): return min(counts[id] ?? 0, need)
        }
    }

    /// 그 펫이 쓴 모자
    func hat(of keeperID: String?) -> HatKind? {
        keeperID.flatMap { logs[$0]?.hat }.flatMap(HatCatalog.hat)
    }

    // MARK: - Affection

    func hearts(of keeperID: String?) -> Int {
        keeperID.flatMap { logs[$0]?.hearts } ?? 0
    }

    func level(of keeperID: String?) -> Int {
        Self.level(forHearts: hearts(of: keeperID))
    }

    static func level(forHearts hearts: Int) -> Int {
        levelThresholds.lastIndex { hearts >= $0 }.map { $0 + 1 } ?? 1
    }

    /// Lv.6 뒤 반짝 발자국 색이 바뀌는 누적 ❤️ (분홍, 금색)
    static let sparkleTiers = [300, 500]

    /// 발자국 색 단계 (0 기본, 1 분홍, 2 금색)
    static func sparkleTier(forHearts hearts: Int) -> Int {
        sparkleTiers.filter { hearts >= $0 }.count
    }

    /// 다음 레벨까지의 누적 ❤️ (마지막 레벨이면 nil)
    func nextThreshold(of keeperID: String?) -> Int? {
        let level = level(of: keeperID)
        return level < Self.levelThresholds.count ? Self.levelThresholds[level] : nil
    }

    /// ❤️를 줌. 그날 그 갈래 상한을 넘으면 주지 않음. 레벨이 오르면 그 레벨
    @discardableResult
    func award(_ source: HeartSource, to keeperID: String, on day: String) -> LevelUp? {
        var log = logs[keeperID] ?? PetLog()
        var tally = log.today?.date == day ? log.today! : DayTally(date: day)
        let given = tally.given[source.rawValue] ?? 0
        let amount = source.dailyCap.map { min(source.amount, max($0 - given, 0)) } ?? source.amount
        guard amount > 0 else { return nil }
        let before = Self.level(forHearts: log.hearts)
        log.hearts += amount
        tally.given[source.rawValue] = given + amount
        log.today = tally
        logs[keeperID] = log
        hasUnsavedHearts = true
        let after = Self.level(forHearts: log.hearts)
        return after > before ? LevelUp(level: after) : nil
    }

    /// 그날 그 갈래로 받은 ❤️
    func given(_ source: HeartSource, to keeperID: String, on day: String) -> Int {
        guard let tally = logs[keeperID]?.today, tally.date == day else { return 0 }
        return tally.given[source.rawValue] ?? 0
    }

    func markHeartsSaved() {
        hasUnsavedHearts = false
    }

    // MARK: - Name and held item

    func name(of keeperID: String?) -> String? {
        keeperID.flatMap { logs[$0]?.name }
    }

    /// 이름 짓기 (Lv.6부터, 앞뒤 공백 빼고 12자까지, 빈 이름은 지움)
    @discardableResult
    func rename(_ keeperID: String, to name: String?) -> Bool {
        guard level(of: keeperID) >= Self.nameLevel else { return false }
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maxNameLength else { return false }
        logs[keeperID, default: PetLog()].name = trimmed.isEmpty ? nil : trimmed
        return true
    }

    func held(of keeperID: String?) -> ItemKind? {
        keeperID.flatMap { logs[$0]?.held }.flatMap(ItemCatalog.item)
    }

    /// 손 소품 (Lv.4부터, 모은 물건만, nil이면 내려놓음)
    @discardableResult
    func hold(_ item: ItemKind?, for keeperID: String) -> Bool {
        if let item {
            guard level(of: keeperID) >= Self.holdLevel, hasFound(item) else { return false }
        }
        logs[keeperID, default: PetLog()].held = item?.id
        return true
    }

    /// 하나 주움. 조건을 채운 모자를 얻고, 주운 펫(keeperID)이 모자가 없으면 새 모자를 바로 씌움
    @discardableResult
    func collect(_ item: ItemKind, on day: String, by keeperID: String? = nil) -> CollectResult {
        let next = count(of: item) + 1
        counts[item.id] = next
        if firstFound[item.id] == nil { firstFound[item.id] = day }
        let unlocked = unlockReached()
        var worn: HatKind?
        if let keeperID, logs[keeperID]?.hat == nil, let first = unlocked.first {
            logs[keeperID, default: PetLog()].hat = first.id
            worn = first
        }
        return CollectResult(count: next, unlocked: unlocked, worn: worn)
    }

    /// 펫에게 모자를 씌움 (nil이면 벗김). 얻은 모자만 됨
    @discardableResult
    func wear(_ hat: HatKind?, on keeperID: String) -> Bool {
        guard let hat else {
            logs[keeperID]?.hat = nil
            return true
        }
        guard isUnlocked(hat) else { return false }
        logs[keeperID, default: PetLog()].hat = hat.id
        newHats.remove(hat.id)
        return true
    }

    /// 새 모자 표시를 지움 (메뉴에서 한 번 본 뒤)
    func markHatsSeen() {
        newHats.removeAll()
    }

    /// 지금 있는 펫의 기록만 남김 (뺀 펫의 모자·친밀도 기록은 지움)
    func keepPets(_ keeperIDs: [String]) {
        let alive = Set(keeperIDs)
        logs = logs.filter { alive.contains($0.key) }
    }

    /// 도감·모자·펫 기록을 모두 지움 (사용자가 확인한 경우만)
    func reset() {
        counts = [:]
        firstFound = [:]
        hats = []
        newHats = []
        logs = [:]
    }

    /// 지금 개수로 조건을 채운 새 모자를 얻음
    fileprivate func unlockReached() -> [HatKind] {
        let reached = HatCatalog.all.filter { !isUnlocked($0) && progress(toward: $0) >= $0.condition.need }
        hats += reached.map(\.id)
        newHats.formUnion(reached.map(\.id))
        return reached
    }

    // MARK: - Saved form

    private struct Record: Codable {
        let version: Int
        let items: [String: Int]
        let firstFound: [String: String]
        var hats: [String]?
        var newHats: [String]?
        var pets: [String: PetLog]?
    }

    func encoded() -> Data {
        let record = Record(version: Self.version, items: counts, firstFound: firstFound, hats: hats, newHats: newHats.sorted(),
                            pets: logs)
        return (try? JSONEncoder().encode(record)) ?? Data()
    }

    /// 저장된 데이터에서 복원. 없으면 빈 도감, 읽을 수 없거나 버전이 다르면 빈 도감과 broken = true (원본은 호출한 쪽이 옮겨 둠).
    /// 모자 기록이 없던 저장이면 지금 개수로 모자를 다시 얻음 (새 모자로 표시)
    static func restore(from data: Data?) -> (treasury: Treasury, broken: Bool) {
        let treasury = Treasury()
        guard let data else { return (treasury, false) }
        guard let record = try? JSONDecoder().decode(Record.self, from: data), record.version == version else {
            return (treasury, true)
        }
        // 모르는 물건(나중 버전에서 뺀 것)도 지우지 않고 그대로 둠, 음수는 버림
        treasury.counts = record.items.filter { $0.value > 0 }
        treasury.firstFound = record.firstFound
        treasury.hats = (record.hats ?? []).filter { HatCatalog.hat($0) != nil }
        treasury.newHats = Set(record.newHats ?? []).intersection(treasury.hats)
        treasury.logs = (record.pets ?? [:]).mapValues { log in
            var log = log
            if let hat = log.hat, !treasury.hats.contains(hat) { log.hat = nil }
            if let held = log.held, ItemCatalog.item(held) == nil { log.held = nil }
            log.hearts = max(log.hearts, 0)
            return log
        }
        _ = treasury.unlockReached()
        return (treasury, false)
    }

    /// 그 맥 달력 기준의 날짜 문자열
    static func day(of date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// This object is responsible for giving every resident pet a lasting ID kept in the settings, in pet order,
/// so later records (affection, hats) stay with the same pet across launches and character changes.
enum KeeperIDs {
    /// 저장된 ID를 펫 수에 맞춤: 모자라면 새로 만들고 남으면 버림
    static func aligned(_ stored: [String], count: Int, make: () -> String = { UUID().uuidString }) -> [String] {
        var ids = Array(stored.prefix(count))
        var seen = Set<String>()
        ids = ids.map { id in
            // 비었거나 겹친 ID는 새로
            guard !id.isEmpty, seen.insert(id).inserted else { return make() }
            return id
        }
        while ids.count < count { ids.append(make()) }
        return ids
    }
}
