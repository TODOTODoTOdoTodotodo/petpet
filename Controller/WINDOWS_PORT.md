# DeskPet 윈도우 이식 검토 (2026-11-20)

일정과 공수는 추정치다. **0단계는 2026-11-20에 끝냈다(8절). 1단계 결과는 9절, 2단계 실행 계획은 10절에 있다.**

## 1. 결론
- **Swift를 유지하고, 운영체제에 붙는 부분만 윈도우용으로 새로 짠다.** Swift는 윈도우용 공식 도구 모음이 있고, `import WinSDK`로 Win32를 직접 부를 수 있다.
- **그대로 쓸 수 있는 부분이 크다.** 펫 행동·월드·물리·조율 코드 약 5,300줄과 검사 약 3,000줄(518개)은 Foundation과 좌표 타입만 쓴다. 이 부분은 AppKit을 쓰지 않는다.
- **새로 짤 부분:** 맥 전용 코드 약 1,650줄(창·메뉴·그리기·입력)이다. 윈도우판은 Win32로 다시 쓰며, 대략 2,000~3,000줄로 본다.
- **대략적인 공수:** 1인 기준 4~7주(추정). 첫 동작판(펫이 창 위를 걷고 트레이 메뉴가 뜸)까지는 2~3주로 본다.
- **다른 방법:**
  - C#이나 Electron으로 전부 다시 짜면, 행동 코드가 두 벌로 갈라져 기능을 더할 때마다 두 번 고쳐야 한다.
  - 그래서 권하지 않는다.

## 2. 지금 구조에서 이미 갈라 둔 곳
- `DesktopSource` 프로토콜(`World/SystemDesktop.swift`)로 모니터·창 목록·맨 앞 앱을 받는다. 윈도우판은 `WindowsDesktop`을 하나 더 만들면 된다.
- `ChaseMode`, `PetBehavior`, 각 Coordinator는 운영체제를 모른다. 입력(포인터 위치, 쉰 시간, 키 누른 수)은 `PetRoster.step(...)` 인자로 들어간다.
- `PetAppearance` 프로토콜이 있어, 그림 쪽(`PetSkin`)만 바꾸면 행동 코드는 그대로다.

## 3. 맥 기능별 윈도우 대응

| 맥 (지금) | 파일 | 윈도우 대응 | 난이도 |
|---|---|---|---|
| `CGWindowListCopyWindowInfo` 창 목록·순서 | `SystemDesktop` | `EnumWindows`(앞→뒤 순서) + `DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)`, `IsWindowVisible`, 가상 데스크톱의 숨은 창은 `DWMWA_CLOAKED`로 제외 | 중 |
| `NSScreen` 모니터·메뉴바 | `SystemDesktop` | `EnumDisplayMonitors` + `GetMonitorInfo`(작업 영역 = 작업 표시줄 제외), `GetDpiForMonitor` | 하 |
| `NSWorkspace` 맨 앞 앱 | `SystemDesktop` | `GetForegroundWindow` + `GetWindowThreadProcessId`, 실행 파일 이름 | 하 |
| `NSPanel` 투명 오버레이 + 클릭 관통 | `ScreenStage` | 모니터마다 `WS_EX_LAYERED · WS_EX_TOOLWINDOW · WS_EX_TOPMOST` 창 + `UpdateLayeredWindow`. 펫 위가 아닐 때는 `WS_EX_TRANSPARENT`로 관통 | 상 |
| SpriteKit 그리기 | `Stage/*`, `PetSkin` | 직접 합성: 32비트 비트맵에 프레임을 정수 배율로 복사(도트라 최근접 확대면 충분). 회전하는 무기만 간단한 회전 복사 | 상 |
| PNG 읽기 (`NSImage`, `CGImage`) | `PetSkin`, `SpriteAlphaScanner` | 공통 `PNGDecoder`(1단계에서 만듦)로 RGBA 픽셀 → 미리 곱한 BGRA로 바꿔 보관. WIC 불필요 | 하 |
| 말풍선 글자·이모지 | `SpeechBubbleNode` | DirectWrite + 컬러 이모지(Segoe UI Emoji) | 중 |
| 메뉴바 👾 메뉴 | `AppController`, `PetLineup` | 트레이 아이콘(`Shell_NotifyIcon`) + `TrackPopupMenu`. 문구는 `MenuText`를 그대로 씀 | 중 |
| 펫 우클릭 메뉴·드래그·클릭 | `PetDragInput` | 오버레이 창의 마우스 메시지, `SetCapture` | 중 |
| 포인터 위치 | `Habitat` | `GetCursorPos` | 하 |
| 포인터 옮기기 (장난) | `CursorMover` | `SetCursorPos` (권한 없음) | 하 |
| 쉰 시간 (잠들기) | `Habitat` | `GetLastInputInfo` | 하 |
| 키 누른 횟수 (타이핑 반응) | `KeyPressCounter` | 전역 카운터가 없음. Raw Input(`RIDEV_INPUTSINK`)으로 키 누름만 셈. 키 내용은 버림. 보안 프로그램이 의심할 수 있어 기본 꺼짐 검토 | 중 |
| 마이크 사용 중 (통화 중 조용히) | `MicrophoneMonitor` | WASAPI `IAudioSessionManager2`로 녹음 장치의 활성 세션 확인 | 중 |
| 캘린더·미리 알림 (EventKit) | `EventKitScheduleSource` | 운영체제 공용 캘린더가 없음. 1차 제외, 나중에 ICS 주소 또는 Outlook 선택 | 상 |
| 설정 (`UserDefaults`) | `PetSettings` | `%APPDATA%\DeskPet\settings.json` | 하 |
| 로그 `~/Library/Logs` | `PetLogger` | `%LOCALAPPDATA%\DeskPet\Logs` | 하 |
| Claude 사용량 파일 | `ClaudeUsageWatcher` | 같은 파일을 `%USERPROFILE%` 아래에서 읽음 (상태줄 설정도 윈도우용 필요) | 하 |
| App Nap 방지 | `AppController` | 해당 없음 | - |
| `.app` + DMG | `package_app.sh` | Swift 실행용 DLL 동봉 + 설치 파일(Inno Setup 또는 MSIX). 서명이 없으면 SmartScreen 경고 | 중 |

## 4. 공통 코드에 필요한 손질 (맥에서 먼저 할 수 있음)
1. **공통 모듈 분리:**
   - 행동·월드 코드를 `DeskPetCore` 타깃으로 옮긴다.
   - 맥 앱은 이 모듈을 쓰는 껍데기만 남긴다.
   - `verify.sh` 검사는 `DeskPetCore`에 그대로 붙인다.
2. **`import CoreGraphics` 정리:**
   - 윈도우의 Foundation에는 `CGFloat`, `CGPoint`, `CGSize`, `CGRect`가 있다.
   - `CGVector`(34곳)는 없을 수 있다. `#if !canImport(CoreGraphics)`로 20줄 정도 보완한다.
3. **스킨 나누기:**
   - `PetSkin`은 지금 `SKTexture`를 들고 있다.
   - 프레임 목록·크기·불투명 영역은 공통 쪽에 두고, 텍스처는 플랫폼 쪽이 갖게 나눈다.
   - `SpriteAlphaScanner`는 `CGImage` 대신 픽셀 배열을 받게 바꾼다.
4. **좌표:**
   - 공통 코드는 지금처럼 "왼쪽 아래 원점, 위로 +y"를 유지한다.
   - 윈도우(왼쪽 위 원점, 아래로 +y)는 `WindowsDesktop`과 그리기 쪽에서만 뒤집는다.
   - 맥의 Quartz → Cocoa 변환과 같은 자리다.

## 5. 윈도우에서 따로 맞출 동작
- **작업 표시줄:**
  - 보통 아래에 있으므로 맥의 메뉴바와 달리 "바닥"이 된다.
  - 작업 영역(`rcWork`)을 바닥·천장으로 쓴다.
  - 작업 표시줄이 자동 숨김이거나 옆에 있는 경우도 확인해야 한다.
- **최대화 창이 흔함:** 기존 "최대화 창은 거꾸로 빼꼼" 규칙을 그대로 쓴다.
- **창 가장자리:**
  - `GetWindowRect`에는 보이지 않는 7px 크기 조절 테두리가 들어 있다. 이를 쓰면 펫이 허공에 선다.
  - 반드시 `DWMWA_EXTENDED_FRAME_BOUNDS`를 쓴다.
- **배율 125%·150%:**
  - 도트가 정수 픽셀이 되도록, 펫 배율을 "기기 픽셀 기준 정수배"로 고른다.
  - 프로세스는 Per-Monitor DPI Aware v2로 둔다.
- **전체 화면 게임·발표:** `SHQueryUserNotificationState`가 바쁨이면 펫을 숨긴다.
- **창 이동 감지:** `SetWinEventHook(EVENT_OBJECT_LOCATIONCHANGE)`로 창이 움직이는 순간을 받는다. 맥처럼 1/30초 폴링을 하지 않아도 된다(창 흔들기에 유리).

## 6. 단계 제안
| 단계 | 내용 | 확인 방법 | 추정 |
|---|---|---|---|
| 0 ✅ | 맥에서 공통 코드 분리, `CGVector` 보완, 스킨 나누기 | 맥 앱 동작 그대로 + 검사 520개 | 완료 |
| 1 ✅ | 윈도우에서 `swift build`(Core만) + 검사 실행 (GitHub Actions 윈도우 러너). 스킨은 WIC 대신 공통 `PNGDecoder`로 읽음 | 같은 검사 통과 | 완료 (9절) |
| 2 | 창 목록·모니터·오버레이·프레임 그리기·트레이 메뉴·클릭·드래그 (10절) | 펫이 창 위를 걷고, 창을 옮기면 따라감 | 2~3주 |
| 3 | 말풍선·무기·스킬 효과·잠들기·포인터 쫓기·장난 | 맥과 같은 장면 비교 | 1~2주 |
| 4 | 타이핑 반응·통화 중·Claude 사용량, zip + PowerShell 한 줄 설치 (10.5절) | 설치 후 새 PC에서 실행 | 1주 |
| 보류 | 일정 말풍선 (윈도우 캘린더 출처 결정 후) | - | - |

## 7. 위험과 정할 것
- **윈도우 PC 필요:**
  - 실제 동작 확인은 윈도우에서만 된다.
  - 단계 1의 검사는 GitHub Actions 윈도우 러너로도 돌릴 수 있다. 이 경우 공개 저장소 여부와 사용 시간을 먼저 정해야 한다.
- **Swift 윈도우 도구:** 맥보다 자료와 디버거 지원이 적다. 막히면 대안이 있다.
  - 공통 모듈을 C 호출 규약(`@_cdecl`)으로 DLL에 담는다.
  - 껍데기는 C#으로 짠다.
- **서명:** 서명 없이 배포하면 SmartScreen 경고가 뜬다. 인증서가 필요한지 정해야 한다.
- **타이핑 반응:** 전역 키 입력을 받는 방식이라 보안 프로그램 경고 가능성이 있다. 기본값을 정해야 한다.
- **일정 말풍선:** ICS 주소, Outlook, 제외 중에서 고른다.

## 8. 0단계 결과 (2026-11-20)
- **폴더:**
  - `Sources/DeskPet/Core`: 54개 파일. Foundation만 쓴다.
  - `Sources/DeskPet/Mac`: 맥 전용 19개 파일. 동작 코드는 고치지 않고 옮기기만 했다.
- **모듈 방식:**
  - 공통 코드를 별도 라이브러리로 떼면, 맥에서 쓰는 모든 선언에 `public`/`package`를 붙여야 한다.
  - 대신 `Package.swift`에서 운영체제별로 폴더를 골라 한 모듈로 묶었다. 맥은 `Core`+`Mac`, 그 밖은 `Core`만이다.
  - 윈도우판도 `Core`+`Windows`로 같은 방식을 쓴다.
- **스킨:**
  - `PetSkin<Frame>`과 `SkinLibrary<Frame>`은 그림 형식을 모른다.
  - PNG를 읽는 일은 `loader`로 받는다. 맥은 `MacSpriteLoader`(NSImage → SKTexture + RGBA 픽셀)이다.
  - 윈도우는 WIC로 같은 `LoadedSprite`를 만들면 된다.
  - 빈 칸 판정(`SpriteAlphaScanner`)은 픽셀 배열만 본다.
  - 정적 저장 속성은 제네릭 타입 안에 둘 수 없어 `FrameInterval`을 파일 수준으로 옮겼다.
- **좌표 타입:**
  - 윈도우 Foundation에는 `CGPoint`·`CGSize`·`CGRect`(midX, insetBy, union, intersects 등)가 있고 `CGVector`가 없다. swift-corelibs-foundation `NSGeometry.swift`로 확인했다.
  - `Core/Portable/PortableGeometry.swift`가 그 경우에만 `CGVector`를 정의한다.
  - 맥에서는 `CGRect` 멤버가 CoreGraphics에 있어, 같은 파일이 한 번 들여온다.
- **경계 검사:** `verify.sh`가 Core에 맥 전용 import가 있거나, Core만으로 타입 검사가 안 되면 실패한다.
- **JSON 숫자:** 스킨 `intervals`는 `NSNumber`가 아니어도 `Double`로 받게 고쳤다. 윈도우 Foundation 차이에 대비한 것이다.
- **아직 모르는 것:**
  - 윈도우에서 실제로 컴파일되는지는 1단계에서 확인한다.
  - 맥 Foundation에만 있는 API를 Core가 쓰는 곳이 있으면 그때 드러난다.
  - `Bundle.main`, `JSONSerialization`, `FileManager`는 윈도우에도 있다.
- **검사에서 Mac 파일을 하나 쓰는 이유:**
  - 검사 실행 파일은 실제 스킨 PNG를 읽어야 해서 `Mac/Skin/MacSprites.swift`를 함께 컴파일한다.
  - 윈도우에서는 이 자리를 WIC 로더로 바꾼다.

## 9. 1단계 결과 (2026-11-20)
- **GitHub Actions `Core portability`** (`.github/workflows/core-portability.yml`):
  - Windows 잡: `windows-latest` + Swift 6.3.3(`compnerd/gha-setup-swift`). `swift build`(맥 밖은 `DeskPetCore`만)와 `scripts/verify.sh`(Git Bash)를 돌린다.
  - Linux 잡: `swift:6.3.3-noble` 컨테이너. 같은 swift-corelibs-foundation이라 윈도우보다 빨리 차이를 잡는다.
  - `main`, `windows-port/**` 브랜치 push와 PR에서 돈다.
- **스킨 PNG 읽기:**
  - WIC 대신 공통 `Core/Skin/PNGDecoder.swift`(inflate 포함, 약 380줄)를 만들었다. 모든 색 형식·1~16비트·tRNS를 읽고, 인터레이스 파일은 읽지 않는다.
  - 맥 검사가 저장소의 스킨 PNG 전부(공개 520장, 로컬 전용 포함 627장)를 Core Graphics와 같은 픽셀로 읽는지 확인한다(알파 일치, 불투명 픽셀 색 ±2).
  - 윈도우판 그리기도 이 해독기를 그대로 쓴다. COM 코드를 짜지 않아도 된다.
- **검사 나누기:**
  - `SkinChecks`: 픽셀 규칙, PNG 해독(작은 PNG를 직접 만들어 필터·팔레트·1비트·고정 허프만 확인), 실제 스킨 폴더 검사를 플랫폼 로더로 받는 `runLibrary`.
  - `MacSkinChecks`(`#if canImport(AppKit)`): Core Graphics 한 픽셀 검사, 해독기 = Core Graphics 비교, 앱의 SpriteKit 로더로 스킨 폴더 검사.
  - 맥 밖에서는 `DecodedFrame`(해독한 픽셀, 동일성 비교)으로 같은 스킨 검사를 돈다. 맥에서도 `-D PORTABLE_CHECKS`로 이 경로를 돌릴 수 있다(644/644).
  - 검사 파일의 `import CoreGraphics`는 지웠다. 맥에서는 Core의 `PortableGeometry`가 한 번 들여온다.
- **Core 손질:** JSON 숫자를 `JSONNumber.double`로 읽는다. corelibs-foundation은 `Int`·`Double`을 주고, 이 값이 `NSNumber`로 바뀌지 않을 수 있다. 쓰는 곳은 스킨 `hatAnchor`·`intervals`와 Claude 사용량이다.
- **`verify.sh`:** `uname`으로 맥·윈도우(MINGW/MSYS)·그 밖을 나눈다. 맥 밖에서는 Core 타입 검사와 검사 실행까지만 하고, SpriteForge 일치 검사(AppKit·ImageIO)는 건너뛴다.
- **검사 수:**
  - 맥(로컬, 비공개 스킨 포함): 646개. 0단계 520개에 PNG 해독·비교 등이 더해졌다.
  - 맥에서 `-D PORTABLE_CHECKS`: 644개. 맥 전용 2개가 빠진다.
  - CI(Windows·Linux): 605개. 저장소에 없는 비공개 스킨 4종의 검사가 빠진다.
- **CI 결과 (2026-11-20, `windows-port/phase1`, run 44686663720):**
  - Windows 잡(Swift 6.3.3, 약 4분)과 Linux 잡(약 1분 반) 모두 `swift build`와 검사 605/605가 통과했다.
  - Core 코드는 고치지 않고도 윈도우 Foundation에서 컴파일됐다. `CGRect` 멤버, `hypot`, `Timer`, `RunLoop`, `String(format:)`, `JSONSerialization`, `FileManager`가 모두 있다.
  - 처음 실패한 곳은 검사 파일 하나였다. `CoreGraphics`만 들여오던 `WorldChecks`에 `import Foundation`을 넣어 고쳤다.

## 10. 2단계 실행 계획 (제안, 시작 전 확인 필요)
목표는 "윈도우에서 펫이 작업 표시줄 위와 창 윗변을 걷고, 창을 옮기면 따라가고, 트레이 메뉴로 끄고 켠다"이다. 윈도우 PC가 없으므로, 단계마다 CI에서 exe를 빌드하고 러너 화면에서 연기 시험(smoke test)을 돌린다. 마지막에는 실제 PC 확인이 한 번 필요하다.

### 10.1 먼저 Core로 올릴 것 (맥에서 하고, 맥 앱 동작은 그대로)
| 지금 (Mac) | 올릴 것 | 이유 |
|---|---|---|
| `World/SystemDesktop.swift`의 `DesktopSource`·`FrontApp` | 프로토콜과 값 타입만 `Core/World` | 윈도우판이 같은 약속을 구현함 |
| `App/PetDragInput.swift` | 클릭·집기·던지기 판정(거리·시간 임계값, 던지는 속도) | 마우스 이벤트 출처만 다름 |
| `App/PetSettings.swift` | 설정 항목과 기본값, 저장소 프로토콜 `SettingsStore` | 맥은 `UserDefaults`, 윈도우는 JSON 파일 |
| `App/PetLineup.swift`·`CollectionMenu.swift` | 메뉴 트리를 데이터로 만드는 부분 (항목·체크·하위 메뉴·명령) | 맥은 `NSMenu`, 윈도우는 `HMENU`로 그리기만 함 |
| `App/Habitat.swift` | 틱마다 입력을 모아 `PetRoster.step` 부르는 순서 | 입력 출처(포인터·쉰 시간)만 주입 |
| `Stage/StageDirector.swift`의 그릴 목록 계산 | 펫마다 그릴 프레임·위치·반전·자르기·모자 자리를 계산한 "그리기 목록" | SpriteKit·비트맵 합성이 같은 목록을 그림 |
- 맥 껍데기는 약 2,300줄이다. 이 중 400~600줄이 Core로 오면 윈도우판 새 코드가 그만큼 준다(추정).

### 10.2 `Sources/DeskPet/Windows` 파일 계획
| 파일 | 책임 | 핵심 API |
|---|---|---|
| `main.swift` | DPI 인식(Per-Monitor v2), 메시지 루프, 60Hz 진행 | `SetProcessDpiAwarenessContext`, `MsgWaitForMultipleObjects` + 고해상도 대기 타이머 |
| `App/WindowsAppController.swift` | 펫 목록·무대·트레이 묶기, 설정 적용 | - |
| `World/WindowsDesktop.swift` | `DesktopSource` 구현: 모니터(작업 영역), 앞→뒤 창 목록, 맨 앞 앱 | `EnumDisplayMonitors`·`GetMonitorInfoW`(`rcWork`), `EnumWindows`·`IsWindowVisible`·`DwmGetWindowAttribute`(`DWMWA_EXTENDED_FRAME_BOUNDS`, `DWMWA_CLOAKED`), `GetForegroundWindow`·`QueryFullProcessImageNameW` |
| `World/WindowsCoordinates.swift` | 가상 화면(왼쪽 위 원점, 아래 +y, 물리 픽셀) ↔ Core(왼쪽 아래, 위 +y) 변환 | 주 모니터 높이 기준 뒤집기 (맥 Quartz → Cocoa와 같은 자리) |
| `Stage/OverlayWindow.swift` | 모니터마다 투명 최상위 창, 펫 위일 때만 클릭 받기 | `WS_EX_LAYERED · TOOLWINDOW · TOPMOST · NOACTIVATE`, `UpdateLayeredWindow`, `WS_EX_TRANSPARENT` 켜고 끄기 |
| `Stage/FrameCompositor.swift` | 32비트 DIB에 프레임을 정수 배율·반전·투명도로 복사, 바뀐 영역만 지우기 | `CreateDIBSection` (미리 곱한 BGRA) |
| `Skin/WindowsSprites.swift` | `PNGDecoder` → 미리 곱한 BGRA 프레임 (`WinSprite`) | 없음 (순수 Swift) |
| `Menu/TrayMenu.swift` | 트레이 아이콘과 팝업 메뉴, 펫 우클릭 메뉴. 문구는 `MenuText` | `Shell_NotifyIconW`, `CreatePopupMenu`·`AppendMenuW`·`TrackPopupMenu` |
| `Input/OverlayPointerInput.swift` | 오버레이의 마우스 메시지 → Core의 클릭·드래그 판정 | `WM_LBUTTONDOWN/MOUSEMOVE/LBUTTONUP`, `SetCapture` |
| `App/WindowsSettingsStore.swift` | `%APPDATA%\DeskPet\settings.json` 읽기·쓰기 | `SHGetKnownFolderPath` 또는 환경 변수 |
| `App/WindowsLogger.swift` | `%LOCALAPPDATA%\DeskPet\Logs\pet_debug.log` | - |
- `Package.swift`: `#elseif os(Windows)`로 `DeskPet` 실행 타깃(`Core`+`Windows`)을 더한다. `user32`·`gdi32`·`dwmapi`·`shell32`·`shcore`를 링크하고, 콘솔 창이 뜨지 않게 `/SUBSYSTEM:WINDOWS`로 링크한다. 리눅스는 지금처럼 `DeskPetCore`만 빌드한다.
- 말풍선 글자는 3단계(DirectWrite)로 미룬다. 2단계에서는 말풍선을 그리지 않는다.

### 10.3 2단계 안의 순서와 확인
| 묶음 | 내용 | CI 확인 | 추정 |
|---|---|---|---|
| 2a ✅ | 10.1 Core 올리기 (맥에서) | 맥 검사 + 맥 앱 동작 그대로 + Windows·Linux 잡 | 완료 (10.6) |
| 2b ✅ | exe 뼈대, 트레이 메뉴(끄기), `WindowsDesktop` | `DeskPet.exe --smoke 8`이 모니터·창 목록을 JSON으로 남기고 끝남. 러너에서 메모장을 띄워 그 창이 목록에 있는지 확인 | 완료 (10.7) |
| 2c ✅ | 오버레이 + 합성기, 작업 표시줄 위 걷기 | 연기 시험 중 화면을 캡처해 아티팩트로 올림 (펫이 보이는지 눈으로 확인) | 완료 (10.8) |
| 2d ✅ | 창 윗변·벽, 창 따라가기, 클릭·끌기·던지기, 펫 우클릭 메뉴, 설정 JSON | 연기 시험이 메모장 창을 옮기고 펫이 따라갔는지 JSON으로 확인 | 완료 (10.9) |
- 러너 화면 캡처와 창 옮기기는 PowerShell(`System.Drawing`, `SetWindowPos`)로 한다. 러너가 화면 없는 상태면 캡처 단계만 건너뛴다.

### 10.4 남는 위험
- **실제 PC 확인:** 러너는 배율 100%·모니터 하나다. 125%·150% 배율, 여러 모니터, 작업 표시줄 자동 숨김은 실제 PC에서 한 번 봐야 한다.
- **Swift 윈도우 실행 파일 크기:** Foundation이 ICU 데이터(수십 MB, 추정)를 함께 싣는다. 크면 Core에서 `FoundationEssentials`만 쓰도록 줄이는 방안을 본다.
- **`WS_EX_TRANSPARENT` 전환 지연:** 펫을 집는 순간 클릭이 뒤 창으로 새면, 맥처럼 포인터 위치로 미리 전환하는 간격을 줄인다.

### 10.5 포장 (4단계 끝)
- `DeskPet-windows.zip`: `DeskPet.exe` + Swift 실행용 DLL(`swiftCore`, `Foundation` 등) + `Assets/Skins`(공개 캐릭터만, `scripts/private-skins.txt` 제외).
- `install.ps1`: `irm https://github.com/TODOTODoTOdoTodotodo/petpet/releases/latest/download/install.ps1 | iex`
  - `%LOCALAPPDATA%\Programs\DeskPet`에 풀고, 시작 메뉴 바로 가기를 만든다. 로그인 시 실행은 선택이다.
  - `-Uninstall`로 지운다. 환경 변수로 받을 주소·설치 폴더를 바꿔 시험할 수 있게 한다(`install.sh`와 같은 방식).
  - PowerShell로 받은 파일에는 인터넷 표시(MOTW)가 붙지 않아, 서명이 없어도 SmartScreen 경고가 보통 뜨지 않는다(추정, 실제 PC에서 확인). 브라우저로 받은 zip은 경고가 뜬다.
- 릴리스 워크플로: 태그 push 때 Windows 러너가 zip을 만들어 Releases에 올린다. 맥 DMG·zip은 지금처럼 로컬에서 만든다.

### 10.6 2a 결과 (2026-11-20)
- **Core로 온 것:**
  - `Core/World/DesktopSource.swift`: `DesktopSource`, `FrontApp`.
  - `Core/Habitat`: `HabitatLoop`(틱 순서·갱신 간격), `HostSenses`, `PetStage`, `PetPointerGesture`.
  - `Core/Stage`: `SceneComposer<Frame>`, `PetDrawing<Frame>`, `ProjectileDrawing`, `ItemDrawing`.
  - `Core/Settings`: `PetSettings`, `SettingsStore`, `JSONFileSettingsStore`. 윈도우는 이 JSON 저장소를 그대로 쓴다.
  - `Core/Menu/MenuNode.swift`: `MenuNode`, `MenuCommand`, `MenuDialogs`, `MenuCommandHandler`.
  - `Core/App`: `AppMenu` + `AppMenuHost`, `PetLineup<Frame>`, `CollectionMenu`, `TreasuryStore` + `TreasuryArchive`.
- **맥에 남은 것:** `NSEvent`·타이머·화면 알림 연결, `MacHostSenses`, `MacMenuRenderer`(`NSMenu`·`NSAlert`), `UserDefaults` 저장소 두 개, SpriteKit 무대.
  - `Mac/App`은 1,274줄에서 630줄로 줄었다(`wc -l` 기준).
- **동작 차이:**
  - 창 목록 갱신 간격 비교에 1e-6초 여유를 두었다. 전에는 1/60초 틱 여섯 번의 합이 0.1초에 살짝 못 미쳐, 실제로는 7틱(약 0.117초)마다 읽었다. 이제 명세대로 0.1초, 움직일 때 1/30초마다 읽는다.
  - 펫 수 저장 형식은 정수에서 실수로 바뀌었다. 예전 정수 값도 읽는다.
  - 이 두 가지 말고는 같다.
- **확인:**
  - 맥 검사 705개. 2a 검사 59개(시계·몸짓·설정·그리기 목록·메뉴)가 더해졌다. 맥 밖 경로(`-D PORTABLE_CHECKS`)는 703개다.
  - 공개 구성 앱을 다시 빌드해 실행했다. 저장된 펫 구성(4마리)·도감(22개)·두 모니터·일정 권한을 그대로 읽고, 쫓기·던지기·결투가 돈다(로그 확인).
  - 메뉴바·우클릭 메뉴를 눌러 보는 확인은 사용자가 한다.
- **CI:** `windows-port/phase2a`(run 44692017944)에서 Windows·Linux 모두 `swift build`와 검사 664/664가 통과했다. 1단계 605개에 2a 검사 59개가 더해졌다. 새 Core 코드도 고치지 않고 윈도우 Foundation에서 컴파일됐다.

### 10.7 2b 결과 (2026-11-20)
- **빌드:** 윈도우에서 `swift build`가 `DeskPet.exe`(Core + `Sources/DeskPet/Windows`)를 만든다. 리눅스는 지금처럼 `DeskPetCore`만 빌드한다.
  - 콘솔 창 없이 띄우는 `/SUBSYSTEM:WINDOWS`는 포장 단계로 미뤘다. 연기 시험이 콘솔 출력을 쓰기 때문이다.
- **새 파일 (`Sources/DeskPet/Windows`, 약 750줄):**
  - `main.swift`: DPI 인식, 숨은 최상위 창, 틱과 창 메시지를 함께 기다리는 루프.
  - `App/FrameTimer.swift`: 고해상도 대기 타이머(`CREATE_WAITABLE_TIMER_HIGH_RESOLUTION`) + `MsgWaitForMultipleObjectsEx`.
  - `App/WindowsApp.swift`: 설정·스킨·펫·도감·메뉴·시계를 2a의 공통 조각으로 묶는다. 트레이 명령을 처리하고 `--smoke` 보고서를 쓴다.
  - `World/WindowsDesktop.swift`: 모니터(작업 영역), 앞→뒤 창 목록(DWM 확장 프레임, 가려진 가상 데스크톱 창·도구 창·작업 표시줄 제외), 맨 앞 앱(실행 파일 이름).
  - `World/WindowsCoordinates.swift`: 좌표를 뒤집는다.
  - `Menu/TrayMenu.swift`: 트레이 아이콘, `MenuNode` → `HMENU`, 하위 메뉴 열림 알림(`WM_INITMENUPOPUP`), 메시지 상자 확인 창.
  - `App/WindowsStorage.swift`·`WindowsHostSenses.swift`, `Skin/WinSprite.swift`, `Stage/HeadlessStage.swift`.
- **연기 시험 (CI, 러너 화면 1024×768, 작업 표시줄 48px):**
  - 모니터 1개를 읽었다. 작업 영역은 아래 48px를 뺀 값이다.
  - 창 목록에 메모장·터미널이 맞는 크기로 들어왔고, 맨 앞 앱은 `notepad.exe`였다.
  - 트레이 아이콘이 떴고, 스킨 19종을 읽었고, 메뉴는 30줄이다.
  - Nabi가 등장해 터미널 창 윗변(y=716)에 내려앉고 인사한 뒤 잠들었다. 러너에는 입력이 없어서다.
  - 8초에 443틱이다. 처음에는 290틱(약 36Hz)이었다. `SetTimer` 16ms가 기본 타이머 간격(15.6ms)에 맞춰 31ms로 늘어난 탓이다. `timeBeginPeriod(1)`로는 바뀌지 않아(288틱), 고해상도 대기 타이머로 바꿨다. 시작 시간(스킨 읽기)이 포함된 수라 진행 중에는 60Hz에 가깝다.
- **좌표 단위(잠정):**
  - 윈도우는 물리 픽셀을 그대로 공통 좌표 단위로 쓰고, 모니터 배율(DPI/96)을 `backingScale`에 담는다.
  - 고배율 모니터에서 펫이 작아 보이는 문제는 2c에서 펫 배율에 모니터 배율을 곱해 맞춘다.
- **아직 없는 것:**
  - 화면에 그리기(2c), 펫 위 클릭·끌기(2d).
  - 이름 짓기 입력 창(3단계, 지금은 건너뜀).
  - 펫 모양 트레이 아이콘(포장 단계, 지금은 기본 앱 아이콘).
  - 일정 항목은 메뉴에 보이지만 동작하지 않는다(보류).

### 10.8 2c 결과 (2026-11-21)
- **그리기 구조:**
  - `Core/Stage/PixelCanvas.swift`(공통): 미리 곱한 BGRA 표면에 그림을 최근접으로 늘려 그린다. 좌우 반전, 위아래 뒤집기(거꾸로 빼꼼), 위쪽 가리기(`shownShare`), 투명도, source-over 겹치기, 가장자리 자르기를 한다. 바뀐 영역도 기록한다.
    - 검사 13개가 맥·윈도우·리눅스에서 돈다.
  - `Windows/Stage/LayeredOverlay.swift`: 모니터마다 `WS_EX_LAYERED · TOOLWINDOW · TOPMOST · NOACTIVATE · TRANSPARENT` 창 하나를 띄운다. 지난번 자리를 지우고 새로 그린 뒤, 바뀐 줄만 DIB로 복사해 `UpdateLayeredWindowIndirect(prcDirty)`로 올린다. 4K 모니터에서도 전체를 매번 올리지 않는다.
  - `Windows/Stage/OverlayStage.swift`: 2a의 `SceneComposer`가 만든 그리기 목록을 각 모니터의 픽셀 자리로 옮긴다. 메뉴의 투명도도 적용한다.
- **좌표 단위:**
  - 2b에서는 물리 픽셀이었다. 2c부터 주 모니터 배율(DPI/96)로 나눈 "포인트"로 바꿨다.
  - 맥의 포인트처럼 150% 배율 화면에서는 펫이 1.5배 픽셀로 그려져, 사용자가 고른 화면 크기대로 보인다.
  - 배율이 다른 모니터를 함께 쓰면 보조 모니터에서도 주 모니터 배율로 그린다(잠정, 실제 PC에서 확인).
  - 100% 화면에서 크기 1.5배는 도트 하나가 1.5픽셀이라 칸이 고르지 않다. 맥 비레티나 화면과 같은 한계다.
- **연기 시험 결과 (CI, 화면 1024×768):**
  - 오버레이 1개, 보이는 펫 픽셀 603개.
  - 화면 캡처에서 Nabi가 메모장 창 윗변에 정확히 서서 자고 있다.
  - 캡처는 PowerShell 7의 `CopyFromScreen`으로 한다. DWM이 합성한 화면이라 레이어드 창도 찍힌다. `CaptureBlt`를 주면 PowerShell 7은 값 자체를 거부하고, Windows PowerShell 5.1은 빈 그림을 남겼다.
  - 틱 수는 캡처와 함께 돌면 350~410(디버그 빌드, 2코어 러너)이다. 바닥값은 300으로, 예전 31ms 타이머(약 290)로 돌아가면 걸린다.
- **아직 없는 것:**
  - 펫 위 클릭·끌기(2d, 지금은 모든 클릭이 관통).
  - 말풍선·모자·손 소품·무기·물건·스킬 효과·숨쉬기·공중제비 회전(3단계).

### 10.9 2d 결과 (2026-11-23)
- **펫 누르기:**
  - `Windows/Input/OverlayPointerInput.swift`: 오버레이의 `WM_LBUTTONDOWN·MOUSEMOVE·LBUTTONUP·RBUTTONDOWN`을 2a의 `PetPointerGesture`로 넘긴다. 위치는 메시지 좌표 대신 화면 커서(맥 `NSEvent.mouseLocation`과 같은 전역 좌표)로 읽는다.
    - 누르는 동안 `SetCapture`로 오버레이 밖까지 끌기를 받는다. 다른 창이 캡처를 가져가면 그 자리에서 놓은 것으로 본다.
    - `WM_MOUSEACTIVATE`에 `MA_NOACTIVATE`를 돌려 펫을 눌러도 앞 창의 포커스를 빼앗지 않는다.
  - 클릭 관통 전환: 맥처럼 틱마다 `routeMouse`가 포인터 아래에 잡을 펫이 있을 때만 그 모니터 오버레이의 `WS_EX_TRANSPARENT`를 끈다.
  - 레이어드 창은 알파 0 픽셀의 클릭을 뒤 창으로 넘긴다. 그래서 펫마다 잡기 영역(`grabRect`)의 빈 픽셀을 알파 1로 칠한다(`PixelCanvas.markHitArea`, 눈에는 안 보임). 다리 사이처럼 빈 곳을 눌러도 맥과 같이 잡힌다.
  - 펫 우클릭 메뉴는 트레이 메뉴와 같은 `TrayMenu.popUp`으로 띄우고, 고른 항목은 `WM_COMMAND` → `AppMenu.perform`으로 간다(맥과 같은 길).
  - 메뉴가 열린 동안은 메뉴가 메시지 루프를 잡아 고해상도 타이머가 돌지 못한다. `SetTimer`(약 30Hz)로 틱을 이어, 트레이·펫 메뉴를 연 동안에도 펫이 멈추지 않는다.
- **창 따라가기·벽·창 윗변:** Core가 이미 하는 일이라 윈도우 쪽 새 코드는 없다. 연기 시험으로 확인만 했다.
- **연기 시험 (`--smoke 14 --drive`, `Windows/App/SmokeDriver.swift`, CI 전용):**
  - 펫이 창 위에 0.5초 넘게 머물면 그 창을 0.1초마다 (20, 12)픽셀씩 6번 옮긴다. Core는 한 번에 250포인트 넘게 움직이면 순간이동으로 보고 떨어뜨리므로, 사람이 끄는 것처럼 나눠 옮긴다.
  - 이어서 `SetCursorPos`와 `SendInput`으로 실제 입력을 보낸다. 펫을 눌러 위로 끌어 놓고(던지기), 2초 뒤 찌르고, 우클릭해 펫 메뉴를 연 뒤 0.6초 뒤 `EndMenu`로 닫는다.
  - 결과(CI run 45093375150): 메모장이 (120, −72)포인트 움직였고, Nabi도 똑같이 (120, −72) 움직여 그 창 위에 남았다. `picked up → released → thrown → idle → poked` 순서로 기록됐고, 펫 메뉴는 25줄로 열렸다. 14초 동안 688틱(초당 49)이었다.
  - 틱 바닥값은 초당 35틱으로 바꿨다(14초 490틱).
  - main 첫 실행(45097327809)에서 걸린 두 가지를 고쳤다. 둘 다 시험 쪽 문제였다.
    - 펫이 메모장 뒤 터미널 창에 먼저 앉은 경우: 그 창을 아래로 옮기자 윗변이 메모장에 가려져 펫이 떨어졌다. Core의 정상 동작이다.
      - 시험은 옮길 창을 먼저 맨 앞으로 올린다(사람이 제목 줄을 끌 때처럼).
      - 다른 프로세스 창은 `HWND_TOP`만으로는 전경 잠금 때문에 앞으로 오지 않는다. 그래서 `HWND_TOPMOST`로 올렸다가 곧바로 `HWND_NOTOPMOST`로 내린다.
    - 펫이 뛰는 중에 우클릭한 경우: 커서를 옮긴 같은 틱에 누르면, 오버레이가 지난 틱 커서 자리 기준으로 아직 클릭 관통 상태라 클릭이 뒤 창으로 갔다.
      - 시험은 겨눈 다음 틱에 누른다.
      - 사람 손은 커서가 펫 위에 여러 틱 머문 뒤 누르므로 이 문제가 없다. 다만 빠르게 지나가며 누르면 한 틱(16ms) 늦을 수 있다(10.4의 전환 지연).
  - 고친 뒤 결과(CI run 45098998770): 펫이 터미널 창에 앉았고, 그 창을 앞으로 올려 옮기자 (120, −72) 똑같이 따라왔다.
- **아직 없는 것:**
  - 말풍선·모자·손 소품·무기·물건·스킬 효과(3단계). 물건이 안 그려지므로 물건 클릭도 3단계에서 확인한다.
  - 이름 짓기 입력 창(3단계).
  - 실제 PC에서 손으로 끌어 보는 확인(배율 125·150%, 여러 모니터, 다른 앱 위 끌기).
