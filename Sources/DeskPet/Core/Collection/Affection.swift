import Foundation

/// 펫이 겪은 일 중 친밀도(❤️)가 되는 것. 펫이 쌓아 두면 AffectionCoordinator가 거둠
enum PetMoment: String, Equatable {
    /// 쓰다듬기 (연달아 3번 화나기는 아님)
    case poked
    /// 앱을 켤 때 내려와 👋
    case greeted
    /// 물건 줍기
    case pickedUp
    /// 티격태격 이김 ✌️
    case wonDuel
    /// 기관차로 도착 🎉
    case arrivedAsEngine
    /// 탑 3층 이상에 올라섬 🎉
    case toppedTower
    /// 포인터 장난 끝까지 😝
    case prankDone

    var source: HeartSource {
        switch self {
        case .poked: return .pokes
        case .greeted: return .greet
        case .pickedUp: return .pickup
        case .wonDuel, .arrivedAsEngine, .toppedTower, .prankDone: return .feats
        }
    }
}

/// ❤️가 쌓이는 갈래: 한 번에 주는 양과 하루 상한
enum HeartSource: String, CaseIterable {
    /// 사용 중 30분 함께 있음
    case together
    case pokes
    case greet
    case pickup
    /// 활약 (기관차·탑·결투·장난)
    case feats

    var amount: Int { self == .pickup ? 2 : 1 }

    /// 하루 상한 (nil이면 없음)
    var dailyCap: Int? {
        switch self {
        case .together: return 16
        case .pokes: return 10
        case .greet: return 1
        case .pickup: return nil
        case .feats: return 5
        }
    }
}

/// This object is responsible for turning what pets do into affection: collecting each pet's moments every tick,
/// adding ❤️ for every 30 minutes of use together, passing them to the treasury (which applies daily caps and levels),
/// keeping each pet's level on the pet, and celebrating a level-up with a hop and ❤️ Lv.N.
final class AffectionCoordinator {
    /// 친밀도를 쌓을 도감 (앱이 넣어 줌. 없으면 사건만 버림)
    var treasury: Treasury?
    /// 오늘 날짜 (검사에서 바꿈)
    var today: () -> String = { Treasury.day(of: Date()) }
    var onEvent: ((String) -> Void)?
    /// 저장할 변화가 생겼을 때 (레벨이 올랐으면 true)
    var onChange: ((Bool) -> Void)?
    private var together: TimeInterval = 0

    /// 함께 있음 ❤️ 간격 (사용 중 시간)
    static let togetherInterval: TimeInterval = 1800
    /// 레벨업 말풍선 시간
    static let celebrateTime: TimeInterval = 2

    func step(dt: TimeInterval, pets: [Pet], idleSeconds: TimeInterval) {
        guard let treasury else {
            pets.forEach { _ = $0.takeMoments() }
            return
        }
        let day = today()
        var leveled = false
        let residents = pets.filter { $0.role == .resident && $0.keeperID != nil }
        for pet in pets {
            let moments = pet.takeMoments()
            guard pet.role == .resident, let id = pet.keeperID else { continue }
            for moment in moments {
                if let up = treasury.award(moment.source, to: id, on: day) {
                    celebrate(up, on: pet)
                    leveled = true
                }
            }
            if !moments.isEmpty { pet.sparkleTier = Treasury.sparkleTier(forHearts: treasury.hearts(of: id)) }
        }
        if idleSeconds < FindingCoordinator.idleLimit { together += dt }
        if together >= Self.togetherInterval {
            together -= Self.togetherInterval
            for pet in residents {
                guard let id = pet.keeperID else { continue }
                if let up = treasury.award(.together, to: id, on: day) {
                    celebrate(up, on: pet)
                    leveled = true
                }
                pet.sparkleTier = Treasury.sparkleTier(forHearts: treasury.hearts(of: id))
            }
        }
        // 쓰다듬기 등 작은 변화도 저장 (상한이 있어 잦지 않음)
        if treasury.hasUnsavedHearts {
            treasury.markHeartsSaved()
            onChange?(leveled)
        }
    }

    /// 펫들에게 도감의 레벨·이름·소품을 반영 (켤 때, 펫 구성이 바뀔 때)
    func sync(_ pets: [Pet]) {
        for pet in pets where pet.role == .resident {
            pet.level = treasury?.level(of: pet.keeperID) ?? 1
            pet.nickname = treasury?.name(of: pet.keeperID)
            pet.heldItem = treasury?.held(of: pet.keeperID)
            pet.sparkleTier = Treasury.sparkleTier(forHearts: treasury?.hearts(of: pet.keeperID) ?? 0)
        }
    }

    @discardableResult
    private func celebrate(_ up: LevelUp, on pet: Pet) -> LevelUp {
        pet.level = up.level
        pet.say("\(Chatter.love) Lv.\(up.level)", for: Self.celebrateTime)
        if pet.support != nil, !pet.isDragged, pet.behavior.towerLevel == nil, pet.behavior.trainRank == nil,
           pet.behavior.isAtLeisure || pet.behavior is IdleBehavior {
            pet.switchTo(AirborneBehavior.hop(name: "levelUp", motionScale: pet.motionScale))
        }
        onEvent?("💗 [\(pet.id)] reached Lv.\(up.level)")
        return up
    }
}

/// 레벨이 오른 순간
struct LevelUp: Equatable {
    let level: Int
}

/// This object is responsible for where a pet holds its item (affection Lv.4): in its front hand at chest height,
/// a little smaller than a dropped item, and hidden while the pet sleeps, peeks from behind a window or carries the pointer.
enum HeldPlacement {
    /// 떨어진 물건보다 작게
    static let shrink: CGFloat = 0.75

    static func rect(on pet: Pet) -> CGRect? {
        guard pet.heldItem != nil, pet.pose.hiddenAbove == nil, pet.animation != .sleep,
              !(pet.behavior is CursorCarryBehavior), pet.opacity >= 0.5 else { return nil }
        let side = 8 * pet.scale * shrink
        let facing = pet.displayFacing
        let forward: CGFloat = facing == .east ? 1 : (facing == .west ? -1 : pet.facing.sign * 0.6)
        let handX = pet.position.x + forward * pet.bodyHalfWidth * 0.9
        let handY = pet.pose.upsideDown ? pet.position.y - pet.bodyHeight * 0.45 : pet.position.y + pet.bodyHeight * 0.45
        return CGRect(x: handX - side / 2, y: handY - side / 2, width: side, height: side)
    }
}
