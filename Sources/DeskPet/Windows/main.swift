import Foundation
import WinSDK

// 모니터마다 배율이 달라도 실제 픽셀로 좌표를 받음 (Per-Monitor DPI Aware v2)
_ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT(bitPattern: -4))
// 기본 타이머 간격(약 15.6ms)에서는 16ms 타이머가 31ms로 늘어남. 이 프로세스만 1ms 간격으로
_ = timeBeginPeriod(1)

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

var message = MSG()
while GetMessageW(&message, nil, 0, 0) {
    _ = TranslateMessage(&message)
    _ = DispatchMessageW(&message)
}
