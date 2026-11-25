import Foundation
import WinSDK

/// This object is responsible for the scene part of the Windows smoke test (`--smoke N --scene`): it raises a pet to the
/// naming level (in the runner's throwaway collection), dresses it (hat, held item, an emoji speech bubble, Lv.5 footstep
/// sparkles) and presses a do-nothing key a few times for the key counter. Once the pointer driver is done it has the pet
/// throw a weapon that hits and one that misses, drops an item and clicks it with real input, and names the pet through
/// the menu's text prompt, filling the prompt like a person would. Last it tries an AI task alert end to end: it opens
/// Notepad, starts a hidden child process under it (as a terminal hosts an AI tool), drops a "waiting" signal naming that
/// child into the inbox, checks a pet holds ✋ with Notepad's icon, minimizes Notepad and pokes the pet so Notepad comes
/// back to the front. What happened goes into the smoke report; what got drawn is the stage's.
/// It only runs on the CI runner; a normal launch never creates it.
final class SceneProbe {
    /// 이름 짓기 시험에 넣는 이름 (한글이 입력 칸을 거쳐 그대로 오는지)
    static let typedName = "나비짱"
    /// 키 수 세기 시험에서 누르는 횟수
    static let keyPresses = 12

    private let roster: PetRoster
    private let treasury: Treasury
    /// AI 작업 알림 받는 함 폴더
    private let inbox: URL
    /// 시험용 호스트 앱(메모장)과 그 아래 숨은 자식 프로세스
    private var host: Process?
    private var hostPID: DWORD?
    private var child: HANDLE?
    private var childPID: DWORD?
    private var holder: Pet?
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

    init(roster: PetRoster, treasury: Treasury, inbox: URL, world: @escaping () -> World, isReady: @escaping () -> Bool,
         perform: @escaping (MenuCommand) -> Void) {
        self.roster = roster
        self.treasury = treasury
        self.inbox = inbox
        self.world = world
        self.isReady = isReady
        self.perform = perform
        steps = [dress, pressKeys, waitForDriver, throwWeapons, wait(1.5), dropItem, clickItem, wait(0.5), openNaming, fillPrompt, checkName,
                 openHost, signalWaiting, waitForNotice, wait(0.6), pokeHolder, checkForeground, closeHost]
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

    /// 첫 펫을 이름 지을 수 있는 레벨까지 올리고(시험용 빈 도감) 모자·든 물건을 씌움 (모자·소품은 저장하지 않음, 그리기만 확인)
    private func dress(_ elapsed: TimeInterval) -> Bool {
        guard let first = roster.residents.first ?? roster.pets.first else { return elapsed > 5 }
        pet = first
        if let keeperID = first.keeperID {
            // 안아 올리기(.pickup)는 하루 상한이 없음. 2개씩이라 75번이면 150개(Lv.6)
            while treasury.level(of: keeperID) < Treasury.nameLevel { treasury.award(.pickup, to: keeperID, on: "smoke") }
            first.level = treasury.level(of: keeperID)
            first.sparkleTier = Treasury.sparkleTier(forHearts: treasury.hearts(of: keeperID))
        }
        results["level"] = first.level
        first.hat = HatCatalog.all.first
        first.heldItem = ItemCatalog.all.first
        results["pet"] = first.id
        return true
    }

    /// 아무 일도 하지 않는 F24 키를 실제 입력으로 12번 누름 (타이핑 반응의 키 수 세기 확인용)
    private func pressKeys(_ elapsed: TimeInterval) -> Bool {
        var inputs: [INPUT] = []
        for _ in 0..<Self.keyPresses {
            for up in [false, true] {
                var input = INPUT()
                input.type = DWORD(INPUT_KEYBOARD)
                input.ki.wVk = WORD(VK_F24)
                input.ki.dwFlags = up ? DWORD(KEYEVENTF_KEYUP) : 0
                inputs.append(input)
            }
        }
        let sent = SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
        if sent != UINT(inputs.count) { notes.append("key SendInput sent \(sent)/\(inputs.count)") }
        results["keysSent"] = Self.keyPresses
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

    /// 펫 옆 위쪽에서 물건을 떨어뜨리고 놓일 때까지 기다림 (4초까지). 자리 고르기는 Core 검사가 맡고 여기서는 그리기·클릭만
    private func dropItem(_ elapsed: TimeInterval) -> Bool {
        if item == nil {
            guard let pet, let kind = ItemCatalog.all.dropFirst().first,
                  let screen = world().screens.first(where: { $0.frame.contains(pet.position) }) ?? world().screens.first else {
                notes.append("no screen to drop an item on")
                return true
            }
            let side = 8 * pet.scale
            let away = pet.position.x + (pet.position.x < screen.frame.midX ? 140 : -140)
            let dropped = DroppedItem(id: "I-probe", kind: kind, scale: pet.scale,
                                      position: CGPoint(x: away, y: screen.visibleFrame.maxY - side - 4))
            roster.finding.release(dropped)
            item = dropped
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

    // MARK: - AI task alert

    /// 메모장을 띄우고 창이 보일 때까지 (8초까지). 새 메모장이 다른 프로세스로 넘어가면 메모장 창을 가진 프로세스로
    private func openHost(_ elapsed: TimeInterval) -> Bool {
        if host == nil {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "C:\\Windows\\System32\\notepad.exe")
            do {
                try process.run()
            } catch {
                notes.append("notepad did not start: \(error)")
                return true
            }
            host = process
        }
        let windows = WindowsAgentHosts.topWindows()
        if let pid = host.map({ DWORD($0.processIdentifier) }), windows[pid] != nil {
            hostPID = pid
        } else if let pid = windows.keys.first(where: { Self.exeName(of: $0)?.lowercased() == "notepad.exe" }) {
            hostPID = pid
        }
        guard hostPID == nil, elapsed < 8 else {
            if hostPID == nil { notes.append("notepad window never appeared") }
            results["agentHostPID"] = hostPID.map { Int($0) } ?? 0
            return true
        }
        return false
    }

    /// 메모장 아래에 창 없는 자식(ping)을 띄우고, 그 자식 번호로 기다림 신호를 받는 함에 넣음 (못 띄우면 메모장 번호로)
    private func signalWaiting(_ elapsed: TimeInterval) -> Bool {
        guard let hostPID else { return true }
        if let spawned = Self.spawnHidden(under: hostPID) {
            childPID = spawned.pid
            child = spawned.process
        } else {
            notes.append("hidden child under notepad failed \(GetLastError()); signaling notepad itself")
        }
        let pid = childPID ?? hostPID
        results["agentSignalPID"] = Int(pid)
        let json = "{\"kind\":\"waiting\",\"source\":\"smoke\",\"pid\":\(pid)}"
        let temporary = inbox.appendingPathComponent("smoke.tmp"), final = inbox.appendingPathComponent("smoke.json")
        do {
            try Data(json.utf8).write(to: temporary)
            try? FileManager.default.removeItem(at: final)
            try FileManager.default.moveItem(at: temporary, to: final)
        } catch {
            notes.append("signal file not written: \(error)")
        }
        return true
    }

    /// 어느 펫이 그 세션의 ✋와 메모장 아이콘을 들 때까지 (4초까지). 들면 메모장을 내려 다른 앱을 보는 상태로
    private func waitForNotice(_ elapsed: TimeInterval) -> Bool {
        guard let pid = childPID ?? hostPID else { return true }
        let topic = "agent:smoke:\(pid)"
        guard let pet = roster.pets.first(where: { $0.noticeTopic == topic }) else {
            if elapsed > 4 { notes.append("no pet took the waiting signal") }
            return elapsed > 4
        }
        holder = pet
        results["agentNotice"] = pet.speech?.text ?? ""
        results["agentBadge"] = pet.speech?.badge?.id ?? ""
        results["agentApp"] = pet.speech?.appProcessID.map { Int($0) } ?? 0
        if let hostPID, let window = WindowsAgentHosts.topWindows()[hostPID] { _ = ShowWindow(window, SW_MINIMIZE) }
        return true
    }

    /// 알림을 든 펫을 겨누고 다음 틱에 실제 클릭 (그 앱을 앞으로 불러와야 함)
    private func pokeHolder(_ elapsed: TimeInterval) -> Bool {
        guard let pet = holder else { return true }
        switch pressed {
        case 0:
            let point = WindowsCoordinates.current().screenPoint(CGPoint(x: pet.grabRect.midX, y: pet.grabRect.midY))
            _ = SetCursorPos(point.x, point.y)
        case 1:
            send(MOUSEEVENTF_LEFTDOWN)
            send(MOUSEEVENTF_LEFTUP)
        default:
            pressed = 0
            return true
        }
        pressed += 1
        return false
    }

    /// 메모장이 맨 앞으로 오고 알림이 닫혔는지 (2초까지)
    private func checkForeground(_ elapsed: TimeInterval) -> Bool {
        guard let hostPID, holder != nil else { return true }
        var pid: DWORD = 0
        if let front = GetForegroundWindow() { _ = GetWindowThreadProcessId(front, &pid) }
        let cleared = holder?.isShowingNotice == false
        guard pid == hostPID, cleared || elapsed > 2 else {
            if elapsed > 2 {
                results["agentForeground"] = false
                results["agentCleared"] = cleared
            }
            return elapsed > 2
        }
        results["agentForeground"] = true
        results["agentCleared"] = cleared
        return true
    }

    private func closeHost(_ elapsed: TimeInterval) -> Bool {
        if let child {
            _ = TerminateProcess(child, 0)
            _ = CloseHandle(child)
            self.child = nil
        }
        // 띄운 메모장만 닫음 (CI가 먼저 띄운 메모장은 창 목록 확인에 쓰므로 그대로)
        if host?.isRunning == true { host?.terminate() }
        host = nil
        return true
    }

    /// 창 없는 ping을 parent의 자식으로 띄움 (PROC_THREAD_ATTRIBUTE_PARENT_PROCESS). 터미널 안 AI 도구를 흉내 냄
    private static func spawnHidden(under parent: DWORD) -> (pid: DWORD, process: HANDLE)? {
        // PROCESS_CREATE_PROCESS
        guard let parentHandle = OpenProcess(DWORD(0x0080), false, parent) else { return nil }
        defer { _ = CloseHandle(parentHandle) }
        var size: SIZE_T = 0
        _ = InitializeProcThreadAttributeList(nil, 1, 0, &size)
        guard size > 0 else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { storage.deallocate() }
        let attributes = OpaquePointer(storage)
        guard InitializeProcThreadAttributeList(attributes, 1, 0, &size) else { return nil }
        defer { DeleteProcThreadAttributeList(attributes) }
        var parentValue: HANDLE? = parentHandle
        // PROC_THREAD_ATTRIBUTE_PARENT_PROCESS
        guard UpdateProcThreadAttribute(attributes, 0, DWORD_PTR(0x0002_0000), &parentValue,
                                        SIZE_T(MemoryLayout<HANDLE>.size), nil, nil) else { return nil }
        var startup = STARTUPINFOEXW()
        startup.StartupInfo.cb = DWORD(MemoryLayout<STARTUPINFOEXW>.size)
        startup.lpAttributeList = attributes
        var info = PROCESS_INFORMATION()
        var command = "C:\\Windows\\System32\\PING.EXE -n 60 127.0.0.1".wide
        // EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW
        let flags = DWORD(0x0008_0000 | 0x0800_0000)
        let created = withUnsafeMutablePointer(to: &startup) { extended in
            extended.withMemoryRebound(to: STARTUPINFOW.self, capacity: 1) { plain in
                CreateProcessW(nil, &command, nil, nil, false, flags, nil, nil, plain, &info)
            }
        }
        guard created, let process = info.hProcess else { return nil }
        _ = CloseHandle(info.hThread)
        return (info.dwProcessId, process)
    }

    private static func exeName(of pid: DWORD) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { _ = CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size) else { return nil }
        return String(wide: buffer, count: Int(size)).split(separator: "\\").last.map(String.init)
    }

    private func send(_ flag: Int32) {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dwFlags = DWORD(truncatingIfNeeded: flag)
        if SendInput(1, &input, Int32(MemoryLayout<INPUT>.size)) != 1 { notes.append("SendInput failed \(GetLastError())") }
    }
}
