# DeskPet 윈도우 이식 검토 (2026-11-20)

일정과 공수는 추정치다. **0단계는 2026-11-20에 끝냈다(8절).**

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
| PNG 읽기 (`NSImage`, `CGImage`) | `PetSkin`, `SpriteAlphaScanner` | WIC(`IWICImagingFactory`)로 BGRA 픽셀 읽기 | 중 |
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
| 1 | 윈도우에서 `swift build`(Core만) + 검사 실행 (GitHub Actions 윈도우 러너 또는 윈도우 PC). 스킨 검사용 WIC 로더 필요 | 같은 검사 통과 | 2~3일 |
| 2 | 창 목록·모니터·오버레이·프레임 그리기·트레이 메뉴·클릭·드래그 | 펫이 창 위를 걷고, 창을 옮기면 따라감 | 2~3주 |
| 3 | 말풍선·무기·스킬 효과·잠들기·포인터 쫓기·장난 | 맥과 같은 장면 비교 | 1~2주 |
| 4 | 타이핑 반응·통화 중·Claude 사용량, 설치 파일 | 설치 후 새 PC에서 실행 | 1주 |
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
