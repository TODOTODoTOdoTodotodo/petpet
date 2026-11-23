import Foundation
import WinSDK

/// 실행 옵션 (`--smoke 초`: 그 시간만 돌고 보고서를 남긴 뒤 끝남, `--report 경로`, `--drive`: 연기 시험 중 창 옮기기·펫 누르기,
/// `--scene`: 연기 시험 중 모자·말풍선·무기·물건 클릭·이름 짓기)
struct LaunchOptions {
    var smokeSeconds: TimeInterval?
    var reportPath = "deskpet-smoke.json"
    var drivesInput = false
    var stagesScene = false

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            switch arguments[index] {
            case "--smoke":
                smokeSeconds = next.flatMap(TimeInterval.init) ?? 10
                index += 1
            case "--report":
                if let next { reportPath = next }
                index += 1
            case "--drive":
                drivesInput = true
            case "--scene":
                stagesScene = true
            default:
                break
            }
            index += 1
        }
    }
}

/// This object is responsible for the Windows app: wiring the shared pieces (settings, skins, pets, collection,
/// status menu, habitat loop) to the Windows readers, the overlays' pointer input, the tray and pet menus and a
/// hidden message window, stepping the loop on each 60Hz frame tick, and applying the settings only the shell owns.
final class WindowsApp {
    /// 숨은 메시지 창의 클래스 이름 (창 목록에서 제외)
    static let windowClass = "DeskPetHost"
    /// 창 프로시저가 찾아오는 앱 (C 콜백은 문맥을 잡을 수 없음)
    static var current: WindowsApp?
    /// 미뤄 둔 메뉴 명령을 메시지 루프에서 실행하라는 메시지 (연기 시험의 이름 짓기)
    static let deferredCommandMessage = UINT(WM_APP) + 2

    private let window: HWND
    private let options: LaunchOptions
    private let settings = PetSettings(store: JSONFileSettingsStore(fileURL: WindowsPaths.settingsFile))
    private let library: SkinLibrary<WinSprite>
    private let skinsDirectory: URL
    private let roster = PetRoster()
    private let desktop = WindowsDesktop()
    private let stage = OverlayStage()
    private let loop: HabitatLoop
    private let tray: TrayMenu
    private let pointerInput: OverlayPointerInput
    private var driver: SmokeDriver?
    private var probe: SceneProbe?
    private var deferredCommand: MenuCommand?
    private let treasuryStore = TreasuryStore(archive: FileTreasuryArchive())
    private var collection: CollectionMenu!
    private var lineup: PetLineup<WinSprite>!
    private var appMenu: AppMenu!
    private let taskbarCreated = RegisterWindowMessageW("TaskbarCreated".wide)
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var ticks = 0
    private var isQuitting = false

    init(window: HWND, options: LaunchOptions) {
        self.window = window
        self.options = options
        skinsDirectory = SkinFolder.locate()
        library = SkinLibrary(directory: skinsDirectory, loader: WinSprite.load)
        loop = HabitatLoop(roster: roster, desktop: desktop, senses: WindowsHostSenses(), stage: stage)
        tray = TrayMenu(window: window)
        pointerInput = OverlayPointerInput(gesture: loop.gesture)
    }

    func start() {
        let log: (String) -> Void = { WindowsLogger.shared.log($0) }
        for name in library.names {
            let blank = library.skins[name]?.blankFrameCount ?? 0
            log("📦 Loaded skin asset: \(name)" + (blank > 0 ? " (skipped \(blank) blank frames)" : ""))
        }
        if library.names.isEmpty { log("⚠️ No skins found at \(skinsDirectory.path)") }

        roster.onEvent = log
        roster.messengerLook = { [weak self] in self?.lineup.nextMessengerLook() }
        loop.onEvent = log
        loop.gesture.onEvent = { [weak self] event in
            log(event)
            self?.driver?.recordGesture(event)
        }
        LayeredOverlay.onMouse = { [unowned self] window, message in self.pointerInput.handle(window, message) }
        loop.quietDuringCalls = settings.quietDuringCalls
        stage.opacity = settings.opacity
        treasuryStore.onEvent = log
        let treasury = treasuryStore.load()
        log("🎒 collection: \(treasury.total) items, \(treasury.counts.count) kinds")
        collection = CollectionMenu(treasury: treasury, store: treasuryStore, roster: roster, dialogs: WindowsMenuDialogs(host: window)) { [unowned self] in
            self.settings.menuLanguage
        }
        collection.onChange = {}
        collection.onEvent = log
        roster.finding.onCollect = { [weak self] kind, petID in self?.collection.collect(kind, by: petID) }
        roster.affection.treasury = treasury
        roster.affection.onChange = { [weak self] levelUp in self?.collection.heartsChanged(levelUp: levelUp) }

        loop.refreshDisplays()
        lineup = PetLineup(library: library, roster: roster, settings: settings) { [unowned self] in self.loop.world }
        lineup.onChange = { [weak self] in self?.collection.syncPets() }
        lineup.petMenuItems = { [weak self] pet in self?.collection.menuNodes(for: pet) ?? [] }
        lineup.petLabel = { [weak self] pet in self?.collection.label(for: pet) ?? pet.id }
        lineup.confirmRemoval = { [weak self] pet in self?.collection.confirmRemoval(of: pet) ?? true }
        appMenu = AppMenu(settings: settings, roster: roster, host: self,
                          lineup: { [unowned self] in self.lineup.statusMenuNodes() },
                          collection: { [unowned self] in self.collection.menuNode() },
                          handlers: [lineup, collection])
        appMenu.applySettingsToPets()
        // 펫을 우클릭한 자리에 그 펫의 메뉴 (고른 항목은 트레이 메뉴처럼 WM_COMMAND로)
        loop.gesture.onContextMenu = { [unowned self] pet, _ in
            let nodes = self.lineup.petMenu(for: pet)
            self.driver?.menuOpened(rows: nodes.count)
            self.tray.popUp(nodes)
        }
        lineup.restore()
        collection.syncPets()

        log(tray.show(tip: "DeskPet") ? "🔔 tray icon shown" : "⚠️ tray icon failed")
        if options.smokeSeconds != nil, options.drivesInput {
            driver = SmokeDriver(roster: roster) { [unowned self] in self.loop.world }
            log("🧪 smoke driver on")
        }
        if options.smokeSeconds != nil, options.stagesScene {
            probe = SceneProbe(roster: roster, treasury: treasury, world: { [unowned self] in self.loop.world }, isReady: { [unowned self] in
                guard let report = self.driver?.report else { return true }
                return (report["finishedSteps"] as? Int) == (report["totalSteps"] as? Int)
            }, perform: { [unowned self] command in
                self.deferredCommand = command
                _ = PostMessageW(self.window, Self.deferredCommandMessage, 0, 0)
            })
            log("🧪 scene probe on")
        }
        loop.tick(now: ProcessInfo.processInfo.systemUptime)
    }

    /// 창 메시지 처리. 처리하지 않으면 nil (기본 처리로 넘김)
    func handle(_ message: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT? {
        switch message {
        case TrayMenu.callbackMessage:
            let event = UINT(truncatingIfNeeded: lParam & 0xFFFF)
            if event == UINT(WM_RBUTTONUP) || event == UINT(WM_LBUTTONUP) {
                tray.popUp(appMenu.nodes())
            }
        case UINT(WM_COMMAND):
            if let command = tray.command(for: UINT(truncatingIfNeeded: wParam & 0xFFFF)) {
                appMenu.perform(command)
            }
        case UINT(WM_TIMER) where wParam == TrayMenu.menuTimerID:
            tick()
        case Self.deferredCommandMessage:
            if let command = deferredCommand {
                deferredCommand = nil
                appMenu.perform(command)
            }
        case UINT(WM_INITMENUPOPUP):
            if let notice = tray.openNotice(for: wParam) { appMenu.perform(notice) }
        case taskbarCreated:
            // 탐색기가 다시 시작되면 트레이 아이콘을 다시 올림
            tray.show(tip: "DeskPet")
        case UINT(WM_DESTROY):
            quit()
        default:
            return nil
        }
        return 0
    }

    /// 60Hz마다 메시지 루프가 부름
    func tick() {
        guard !isQuitting else { return }
        let now = ProcessInfo.processInfo.systemUptime
        loop.tick(now: now)
        driver?.tick(now: now)
        probe?.tick(now: now)
        ticks += 1
        if let seconds = options.smokeSeconds, now - startedAt >= seconds {
            writeSmokeReport()
            quit()
        }
    }

    private func quit() {
        guard !isQuitting else { return }
        isQuitting = true
        tray.remove()
        stage.close()
        WindowsLogger.shared.log("👋 quit")
        PostQuitMessage(0)
    }

    // MARK: - Smoke report

    /// 연기 시험 보고서: 모니터·창 목록·맨 앞 앱·펫·그린 수 (CI가 읽어 확인)
    private func writeSmokeReport() {
        func box(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height].map(Double.init) }
        let report: [String: Any] = [
            "displays": desktop.displays().map {
                ["name": $0.name, "frame": box($0.frame), "visible": box($0.visibleFrame), "scale": Double($0.backingScale)]
            },
            "windows": desktop.windows().prefix(40).map { ["owner": $0.owner, "frame": box($0.frame)] },
            "frontmost": desktop.frontmostApp()?.bundleID ?? "",
            "skins": library.names,
            "skinsDirectory": skinsDirectory.path,
            "pets": roster.pets.map {
                ["id": $0.id, "look": $0.appearance.name, "x": Double($0.position.x), "y": Double($0.position.y), "behavior": $0.behavior.name]
            },
            "drawings": stage.lastDrawings,
            "overlays": stage.summary,
            "stage": stage.drawReport,
            "menuRows": appMenu.nodes().count,
            "tray": tray.isShown,
            "ticks": ticks,
            "drive": driver?.report ?? [:],
            "scene": probe?.report ?? [:],
            "settingsFile": WindowsPaths.settingsFile.path,
            "log": WindowsLogger.shared.fileURL.path,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = URL(fileURLWithPath: options.reportPath)
        try? data.write(to: url)
        WindowsLogger.shared.log("🧪 smoke report written to \(url.path)")
    }
}

extension WindowsApp: AppMenuHost {
    /// Claude 사용량은 4단계에서
    var usageSummary: String? { nil }

    /// 일정 말풍선은 윈도우 캘린더 출처를 정한 뒤 (보류)
    var calendarAccessDenied: Bool { false }

    func settingChanged(_ command: MenuCommand) {
        switch command {
        case .toggle(.quietDuringCalls):
            loop.quietDuringCalls = settings.quietDuringCalls
        case .opacity:
            stage.opacity = settings.opacity
        default:
            break
        }
    }

    func run(_ action: PlatformAction) {
        switch action {
        case .openLog:
            _ = ShellExecuteW(nil, "open".wide, WindowsLogger.shared.fileURL.path.wide, nil, nil, SW_SHOWNORMAL)
        case .quit:
            quit()
        case .allowCalendarAccess:
            break
        }
    }
}
