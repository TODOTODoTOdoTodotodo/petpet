import Foundation
import WinSDK

// 모니터마다 배율이 달라도 실제 픽셀로 좌표를 받음 (Per-Monitor DPI Aware v2)
_ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))

/// 숨은 창의 메시지를 앱으로 넘기고, 앱이 처리하지 않은 메시지는 기본 처리
let windowProcedure: WNDPROC = { window, message, wParam, lParam in
    if let result = WindowsApp.current?.handle(message, wParam, lParam) { return result }
    return DefWindowProcW(window, message, wParam, lParam)
}

let instance = GetModuleHandleW(nil)
let className = WindowsApp.windowClass.wide
let registered = className.withUnsafeBufferPointer { name -> ATOM in
    var windowClass = WNDCLASSEXW()
    windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    windowClass.lpfnWndProc = windowProcedure
    windowClass.hInstance = instance
    windowClass.lpszClassName = name.baseAddress
    return RegisterClassExW(&windowClass)
}

// 보이지 않는 최상위 창: 타이머·트레이 메시지·메뉴 명령을 받음 (메뉴가 닫히려면 최상위 창이어야 함)
guard registered != 0,
      let host = CreateWindowExW(0, className, "DeskPet".wide, 0, 0, 0, 0, 0, nil, nil, instance, nil) else {
    print("DeskPet: could not create the host window (error \(GetLastError()))")
    exit(1)
}

let app = WindowsApp(window: host, options: LaunchOptions(arguments: CommandLine.arguments))
WindowsApp.current = app
app.start()

// 60Hz 진행: SetTimer는 기본 타이머 간격(약 15.6ms)에 묶여 16ms가 31ms로 늘어나므로,
// 고해상도 대기 타이머를 메시지와 함께 기다림
let frameTimer = FrameTimer(milliseconds: 16)
var message = MSG()
var running = true
while running {
    if frameTimer.waitForTickOrMessage() { app.tick() }
    while PeekMessageW(&message, nil, 0, 0, UINT(PM_REMOVE)) {
        if message.message == UINT(WM_QUIT) {
            running = false
            break
        }
        _ = TranslateMessage(&message)
        _ = DispatchMessageW(&message)
    }
}
