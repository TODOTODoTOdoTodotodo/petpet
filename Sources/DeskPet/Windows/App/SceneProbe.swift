import Foundation
import WinSDK

/// This object is responsible for the phase-3 part of the Windows smoke test (`--smoke N --scene`): it dresses a pet
/// (hat, held item, an emoji speech bubble), and once the pointer driver is done it has the pet throw a weapon that hits
/// and one that misses, drops an item and clicks it with real input, and names the pet through the menu's text prompt,
/// filling the prompt like a person would. What happened goes into the smoke report; what got drawn is the stage's.
/// It only runs on the CI runner; a normal launch never creates it.
final class SceneProbe {
    /// 이름 짓기 시험에 넣는 이름 (한글이 입력 칸을 거쳐 그대로 오는지)
    static let typedName = "나비짱"

    private let roster: PetRoster
    private let world: () -> World
    private let isReady: () -> Bool
    /// 앱 메뉴 명령을 메시지 루프에서 실행 (입력 창은 모달이라 틱 안에서 바로 열지 않음)
    private let perform: (MenuCommand) -> Void
    private var steps: [(TimeInterval) -> Bool] = []
    private var index = 0
    private var stepStarted: TimeInterval?
    private var now: TimeInterval = 0
    private var lastSpeech: TimeInterval = -10
    private var pet: Pet?
    private var item: DroppedItem?
    private var pressed = 0
    private var notes: [String] = []
    private var results: [String: Any] = [:]

    init(roster: PetRoster, world: @escaping () -> World, isReady: @escaping () -> Bool, perform: @escaping (MenuCommand) -> Void) {
        self.roster = roster
        self.world = world
        self.isReady = isReady
        self.perform = perform
        steps = [dress, waitForDriver, throwWeapons, wait(1.5), dropItem, clickItem, wait(0.5), openNaming, fillPrompt, checkName]
    }

    var report: [String: Any] {
        results.merging(["finishedSteps": index, "totalSteps": steps.count, "notes": notes]) { first, _ in first }
    }

    /// 틱마다 (메뉴·입력 창이 열린 동안에는 그 타이머로) 부름
    func tick(now: TimeInterval) {
        self.now = now
        // 말풍선이 늘 보이게 1.2초마다 다시 말함 (컬러 이모지 확인용)
        if let pet, now - lastSpeech >= 1.2 {
            pet.say(Chatter.love, for: 1.5)
            lastSpeech = now
        }
        guard index < steps.count else { return }
        let started = stepStarted ?? now
        stepStarted = started
        if steps[index](now - started) {
            index += 1
            stepStarted = nil
        }
    }

    // MARK: - Steps

    private func wait(_ seconds: TimeInterval) -> (TimeInterval) -> Bool {
        { $0 >= seconds }
    }

    /// 첫 펫에 모자·든 물건 (저장하지 않음, 그리기만 확인)
    private func dress(_ elapsed: TimeInterval) -> Bool {
        guard let first = roster.residents.first ?? roster.pets.first else { return elapsed > 5 }
        pet = first
        first.hat = HatCatalog.all.first
        first.heldItem = ItemCatalog.all.first
        results["pet"] = first.id
        return true
    }

    private func waitForDriver(_ elapsed: TimeInterval) -> Bool {
        isReady() || elapsed > 20
    }

    /// 맞는 무기 하나, 빗나가는 무기 하나 (빗나가면 반짝임 대신 먼지)
    private func throwWeapons(_ elapsed: TimeInterval) -> Bool {
        guard let pet else { return true }
        let target = CGPoint(x: pet.position.x + 160 * pet.facing.sign, y: pet.position.y + 60)
        pet.hurl(.club, at: target)
        pet.hurl(.rock, at: CGPoint(x: target.x - 60 * pet.facing.sign, y: target.y + 40), missed: true)
        return true
    }

    /// 물건을 떨어뜨리고 놓일 때까지 기다림 (4초까지)
    private func dropItem(_ elapsed: TimeInterval) -> Bool {
        if item == nil {
            item = roster.finding.drop(ItemCatalog.all.dropFirst().first, in: world(), pets: roster.pets, screenID: nil)
            if item == nil {
                notes.append("no ledge to drop an item on")
                return true
            }
        }
        if item?.isResting == true { return true }
        if elapsed > 4 { notes.append("item never came to rest") }
        return elapsed > 4
    }

    /// 놓인 물건 가운데를 겨누고, 다음 틱에 실제 클릭 (누르기 전 틱에 오버레이가 클릭을 받게 바뀌어야 함)
    private func clickItem(_ elapsed: TimeInterval) -> Bool {
        guard let item, roster.finding.items.contains(where: { $0 === item }), item.isResting else {
            notes.append("item gone before the click")
            return true
        }
        switch pressed {
        case 0:
            let point = WindowsCoordinates.current().screenPoint(CGPoint(x: item.rect.midX, y: item.rect.midY))
            _ = SetCursorPos(point.x, point.y)
        case 1:
            send(MOUSEEVENTF_LEFTDOWN)
            send(MOUSEEVENTF_LEFTUP)
        default:
            // 클릭한 물건은 잠깐 반짝임
            results["itemClicked"] = item.flashLeft > 0
            results["item"] = item.kind.id
            pressed = 0
            return true
        }
        pressed += 1
        return false
    }

    private func openNaming(_ elapsed: TimeInterval) -> Bool {
        guard let keeperID = pet?.keeperID else {
            notes.append("pet has no keeper id to rename")
            return true
        }
        perform(.rename(keeperID: keeperID))
        return true
    }

    /// 입력 창이 뜨면 사람처럼 칸에 이름을 넣고 저장을 누름 (3초까지)
    private func fillPrompt(_ elapsed: TimeInterval) -> Bool {
        guard let prompt = FindWindowW(TextPrompt.windowClass.wide, nil) else {
            if elapsed > 3 { notes.append("naming prompt did not open") }
            return elapsed > 3
        }
        results["promptOpened"] = true
        guard elapsed > 0.4, let edit = GetDlgItem(prompt, TextPrompt.editID) else { return false }
        _ = SetWindowTextW(edit, Self.typedName.wide)
        _ = PostMessageW(prompt, UINT(WM_COMMAND), WPARAM(IDOK), 0)
        return true
    }

    private func checkName(_ elapsed: TimeInterval) -> Bool {
        guard pet?.nickname == Self.typedName else {
            if elapsed > 2 { results["renamed"] = false }
            return elapsed > 2
        }
        results["renamed"] = true
        return true
    }

    private func send(_ flag: Int32) {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dwFlags = DWORD(truncatingIfNeeded: flag)
        if SendInput(1, &input, Int32(MemoryLayout<INPUT>.size)) != 1 { notes.append("SendInput failed \(GetLastError())") }
    }
}
