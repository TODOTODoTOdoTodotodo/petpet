import Foundation
import WinSDK

/// This object is responsible for the scripted part of the Windows smoke test (`--smoke N --drive`): once a pet
/// rests on a window it slides that window a little at a time and records whether the pet rode along, then
/// presses the pet with real input (`SendInput`) to drag and throw it, poke it and open its right-click menu,
/// closing that menu again. What happened goes into the smoke report for CI to check.
/// It only runs on the CI runner; a normal launch never creates it.
final class SmokeDriver {
    /// 창을 옮기는 횟수와 한 번에 옮기는 픽셀 (Core는 한 번에 250포인트 넘게 움직이면 순간이동으로 봄)
    private static let windowSteps = 6
    private static let windowStep = (x: LONG(20), y: LONG(12))

    private let roster: PetRoster
    private let world: () -> World
    private var steps: [(TimeInterval) -> Bool] = []
    private var index = 0
    private var stepStarted: TimeInterval?

    private var rider: Pet?
    private var riderSince: TimeInterval?
    private var windowID: UInt32?
    private var before: (pet: CGPoint, window: CGRect)?
    private var moved = 0
    private var lastMove: TimeInterval = -1
    private var pressed = 0
    private(set) var gestures: [String] = []
    private var notes: [String] = []
    private var follow: [String: Any] = [:]
    private var menuRows = 0
    private var menuOpenedAt: TimeInterval?
    private var now: TimeInterval = 0

    init(roster: PetRoster, world: @escaping () -> World) {
        self.roster = roster
        self.world = world
        steps = [
            findRider, slideWindow, wait(1.0), recordFollow,
            aim, wait(0.25), drag,
            wait(2.0), aim, wait(0.25), poke,
            wait(0.8), aim, wait(0.25), openMenu, closeMenu,
        ]
    }

    /// 틱마다 (메뉴가 열린 동안에는 메뉴 타이머로) 부름
    func tick(now: TimeInterval) {
        self.now = now
        guard index < steps.count else { return }
        let started = stepStarted ?? now
        stepStarted = started
        if steps[index](now - started) {
            index += 1
            stepStarted = nil
        }
    }

    func recordGesture(_ event: String) {
        gestures.append(event)
    }

    func menuOpened(rows: Int) {
        menuRows = rows
        menuOpenedAt = now
    }

    var report: [String: Any] {
        ["finishedSteps": index, "totalSteps": steps.count, "follow": follow, "gestures": gestures,
         "petMenuRows": menuRows, "notes": notes]
    }

    // MARK: - Steps

    private func wait(_ seconds: TimeInterval) -> (TimeInterval) -> Bool {
        { $0 >= seconds }
    }

    /// 창 위에 0.5초 넘게 머무는 펫을 찾음 (8초까지)
    private func findRider(_ elapsed: TimeInterval) -> Bool {
        let candidate = roster.pets.first { $0.isTangible && !$0.isDragged && $0.support?.owner.windowID != nil }
        if let candidate, candidate === rider, candidate.support?.owner.windowID == windowID {
            if let since = riderSince, now - since >= 0.5, let windowID, let window = world().window(id: windowID) {
                before = (candidate.position, window.frame)
                follow["owner"] = window.owner
                follow["pet"] = candidate.id
                return true
            }
        } else {
            rider = candidate
            windowID = candidate?.support?.owner.windowID
            riderSince = now
        }
        guard elapsed < 8 else {
            // 창 옮기기는 건너뛰고(창이 없으면 그 단계들이 바로 끝남) 포인터 시험으로
            follow["error"] = "no pet rested on a window"
            windowID = nil
            return true
        }
        return false
    }

    /// 0.1초마다 오른쪽 아래로 조금씩 옮김 (사람이 끄는 것처럼)
    private func slideWindow(_ elapsed: TimeInterval) -> Bool {
        guard let windowID, let window = HWND(bitPattern: UInt(windowID)) else { return true }
        guard now - lastMove >= 0.1 else { return false }
        lastMove = now
        var rect = RECT()
        guard GetWindowRect(window, &rect) else {
            notes.append("GetWindowRect failed \(GetLastError())")
            return true
        }
        let flags = UINT(SWP_NOSIZE) | UINT(SWP_NOZORDER) | UINT(SWP_NOACTIVATE)
        if !SetWindowPos(window, nil, rect.left + Self.windowStep.x, rect.top + Self.windowStep.y, 0, 0, flags) {
            notes.append("SetWindowPos failed \(GetLastError())")
            return true
        }
        moved += 1
        return moved >= Self.windowSteps
    }

    private func recordFollow(_ elapsed: TimeInterval) -> Bool {
        guard let before, let rider, let windowID, let window = world().window(id: windowID) else {
            follow["error"] = follow["error"] ?? "window or pet gone"
            return true
        }
        follow["windowMoved"] = [window.frame.minX - before.window.minX, window.frame.maxY - before.window.maxY].map(Double.init)
        follow["petMoved"] = [rider.position.x - before.pet.x, rider.position.y - before.pet.y].map(Double.init)
        follow["stillOnWindow"] = rider.support?.owner.windowID == windowID
        follow["windowSteps"] = moved
        return true
    }

    /// 펫 잡기 영역 가운데로 커서를 옮김
    @discardableResult
    private func aim(_ elapsed: TimeInterval = 0) -> Bool {
        guard let pet = target else {
            notes.append("no pet to aim at")
            return true
        }
        let point = WindowsCoordinates.current().screenPoint(CGPoint(x: pet.grabRect.midX, y: pet.grabRect.midY))
        _ = SetCursorPos(point.x, point.y)
        return true
    }

    /// 누르고 10틱 동안 위로 끌어올린 뒤 놓음 (던지기)
    private func drag(_ elapsed: TimeInterval) -> Bool {
        if pressed == 0 {
            aim()
            send(MOUSEEVENTF_LEFTDOWN)
        } else if pressed <= 10 {
            var point = POINT()
            _ = GetCursorPos(&point)
            move(to: POINT(x: point.x - 4, y: point.y - 8))
        } else {
            send(MOUSEEVENTF_LEFTUP)
            pressed = 0
            return true
        }
        pressed += 1
        return false
    }

    private func poke(_ elapsed: TimeInterval) -> Bool {
        if pressed == 0 {
            aim()
            send(MOUSEEVENTF_LEFTDOWN)
            pressed = 1
            return false
        }
        send(MOUSEEVENTF_LEFTUP)
        pressed = 0
        return true
    }

    private func openMenu(_ elapsed: TimeInterval) -> Bool {
        aim()
        send(MOUSEEVENTF_RIGHTDOWN)
        send(MOUSEEVENTF_RIGHTUP)
        return true
    }

    /// 메뉴가 뜨고 0.6초 뒤 닫음 (2초 안에 안 뜨면 그만둠)
    private func closeMenu(_ elapsed: TimeInterval) -> Bool {
        if let opened = menuOpenedAt {
            guard now - opened >= 0.6 else { return false }
            _ = EndMenu()
            return true
        }
        if elapsed >= 2 { notes.append("pet menu did not open") }
        return elapsed >= 2
    }

    // MARK: - Input

    private var target: Pet? {
        rider.flatMap { pet in roster.pets.contains { $0 === pet } ? pet : nil } ?? roster.pets.first { $0.isTangible }
    }

    private func send(_ flag: Int32) {
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dwFlags = DWORD(truncatingIfNeeded: flag)
        if SendInput(1, &input, Int32(MemoryLayout<INPUT>.size)) != 1 { notes.append("SendInput failed \(GetLastError())") }
    }

    /// 가상 화면 전체를 0~65535로 나눈 절대 좌표로 옮김 (상대 이동은 포인터 가속을 탐)
    private func move(to point: POINT) {
        let left = GetSystemMetrics(SM_XVIRTUALSCREEN), top = GetSystemMetrics(SM_YVIRTUALSCREEN)
        let width = max(GetSystemMetrics(SM_CXVIRTUALSCREEN) - 1, 1), height = max(GetSystemMetrics(SM_CYVIRTUALSCREEN) - 1, 1)
        var input = INPUT()
        input.type = DWORD(INPUT_MOUSE)
        input.mi.dx = LONG((Int(point.x - left) * 65535) / Int(width))
        input.mi.dy = LONG((Int(point.y - top) * 65535) / Int(height))
        input.mi.dwFlags = DWORD(truncatingIfNeeded: MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK)
        if SendInput(1, &input, Int32(MemoryLayout<INPUT>.size)) != 1 { notes.append("SendInput move failed \(GetLastError())") }
    }
}
