# DeskPet 프로젝트 인수인계 문서 (Handover Document)

macOS 상주형 데스크톱 펫 **DeskPet**의 구조, 빌드·검증 절차, 스킨 추가 방법, 문제 해결 이력을 정리한 문서입니다.
2026-11-17에 핵심부(월드 인식·펫 행동·렌더링)를 새로 작성했습니다. 설계 원칙은 [`Controller/DESKTOP_PET_CONTROLLER.md`](Controller/DESKTOP_PET_CONTROLLER.md)를 따릅니다.

---

## 1. 개요

* **언어·플랫폼:** Swift 5.9, macOS 13.0+ (공통 코드 `Core`는 윈도우 이식 대비 Foundation만)
* **프레임워크:** AppKit(`NSPanel`, `NSStatusBar`), SpriteKit(그리기), CoreGraphics(`CGWindowListCopyWindowInfo`)
* **주요 기능**
  1. **마우스 관통:** 펫 위에 커서가 있을 때만 그 모니터의 패널이 클릭을 받음.
  2. **보이는 창만 발판·벽:** 앞 창에 가려진 윗변·옆변은 쓰지 않음.
  3. **창 추적:** 서 있는 창을 옮기면 같이 이동, 창이 닫히면 낙하. 오르던 창이 움직여도 벽에 붙어 따라감.
  4. **등반:** 꼭대기까지 보이고 올라설 자리·머리 공간이 있을 때만 오르고, 올라서면 지붕 안쪽으로 걸어감.
  5. **다중 모니터:** 전역 좌표 하나로 처리. 옆 모니터로 걸어감. 위아래 모니터는 바닥·천장이 막혀 있고, 보고 있는 창이 펫 없는 모니터에 있으면 펫 하나가 사라졌다 그 모니터에 나타나 건너감. 화면 구성이 바뀌어도 펫 유지.
  6. **드래그·던지기:** 펫을 집어 옮기고, 놓을 때의 손 움직임으로 던져짐.
  7. **클릭 반응:** 짧게 클릭하면 깡충 + ❤️, 연달아 3번이면 💢 + 도망. 자는 펫은 깸.
  8. **잠들기:** 키보드·마우스 입력이 3분 없으면 졸다가(…) 잠듦(Zzz), 입력이 생기면 깜짝 깸(!).
  9. **펫끼리 어울리기:** 같은 발판에서 마주치면 👋 인사, 가끔 다른 펫을 따라감.
  10. **일정 말풍선:** 맥 캘린더 일정 10분 전·시작 시각, 미리 알림 마감 시각에 말풍선 (`10분 뒤 · 주간 회의`). 펫을 클릭해 확인할 때까지 유지. 일정이 여러 개면 다른 스킨의 전령 펫이 내려와 하나씩 맡고, 확인하면 👋 하고 떠남. 메뉴에서 끄기·제목 숨김.
  11. **스킬 도약:** 다른 앱으로 바꾸면 한가한 펫이 캐릭터별 스킬(Goblin 장대높이뛰기, Radish 불꽃 로켓, Boy·Girl 칼 도약)로 그 앱 창 위에 올라섬. 최대화 창이면 윗변 뒤로 숨었다가 거꾸로 머리만 빼꼼 내밀고 두리번거린 뒤(또는 클릭 시) 내려옴. 30초에 한 번, 메뉴 **Skill Jumps**로 끄기.
  12. **창 흔들어 털기:** 펫이 올라탄 창을 좌우(또는 위아래)로 빠르게 흔들면 펫들이 💫 하고 흩어지며 튕겨 나가고, 내려와서 잠시 어지러워함.
  13. **펫 탑:** 마주친 펫이 가끔 다른 펫 머리에 올라타고, 근처 펫이 하나씩 맨 위로 올라와 최대 4층. 잠시 뒤, 또는 아래 펫을 클릭·집기·창 흔들기로 무너짐.
  14. **겹치지 않기:** 같은 발판의 펫끼리 겹치지 않음. 길이 막히면 뛰어넘거나 ⚔️ 결투를 걸어 이기면 넘어가고, 지면 돌아섬. 모일 때는 나란히 줄 섬. 겹쳐 내려앉으면 옆으로 비킴.
  15. **등장 연출:** 앱을 켜거나 펫을 더하면 펫들이 메뉴바 밑에서 한 마리씩 지금 보는 창 위로 떨어져 나란히 내려앉고 👋.
  16. **타이핑 반응:** 키를 빠르게 누르는 동안 펫이 하나씩 따라 두드림(칠수록 빨리), 아주 빠르면 🔥. 누른 횟수만 세고 내용은 모름. 메뉴 **React To Typing**.
  17. **기차놀이:** 같은 발판의 한가한 펫들이 가끔 줄줄이 기차놀이. 맨 앞 펫이 🚂 하며 끌고, 나머지가 간격을 맞춰 따라오다 🎉 하고 해산.
  18. **포인터 장난 (기본 꺼짐):** 메뉴 **Pointer Pranks**를 켜면, 펫 곁에 멈춘 포인터를 펫이 가끔 잡고 1초쯤 들고 달아남. 마우스를 움직이면 바로 돌려줌.
  19. **설정 저장:** 스킨·크기(1.0/1.5/2.0/2.5)·투명도·펫 수·일정·메뉴 언어 설정을 다음 실행에도 유지.
  20. **메뉴 언어:** 메뉴 **Language · 언어**에서 English·한국어 선택. 처음에는 맥 언어를 따름.
  21. **물건 줍기 (수집 1단계):** 사용 중 6~18분마다 창 위나 바닥에 물건(10종 + 계절 2종, 드문 것 4종)이 떨어지면 가까운 펫이 주워 ✨. 메뉴 **Collection · 도감**에 개수가 쌓이고 껐다 켜도 유지. 물건을 클릭하면 펫이 바로 감.
     **모자 (수집 2단계):** 모은 수로 모자 8종을 얻음(예: 도토리 5개 → 도토리 모자). 얻는 순간 주운 펫이 🎩 하고 씀. 펫 우클릭 ▸ **Hat · 모자**로 바꿈.
     **친밀도 (수집 3단계):** 쓰다듬기·함께 있기·줍기·활약으로 펫마다 ❤️가 쌓여 Lv.6까지. Lv.2 한 바퀴, Lv.3 공중제비, Lv.4 손 소품, Lv.5 반짝 발자국(❤️ 300 분홍·500 금색), Lv.6 이름 짓기.
     **계절 물건 (수집 4단계):** 12~2월 눈송이, 3~4월 벚꽃. 드문 물건이 놓이면 펫들이 돌아보며 !, 날아갈 때 반짝임 꼬리.
  22. **로그:** `~/Library/Logs/DeskPet/pet_debug.log`에 행동 전환만 기록.

---

## 2. 파일 구조

```text
private/
├── Controller/
│   ├── DESKTOP_PET_CONTROLLER.md  # 설계 명세 (코드 수정 전 선행 갱신)
│   ├── WINDOWS_PORT.md            # 윈도우 이식 검토와 단계 (0단계 완료)
│   └── HANDOVER.md                # 본 문서 사본
├── Sources/DeskPet/
│   ├── Core/                      # 운영체제를 모르는 공통 코드 (Foundation만, 윈도우판도 그대로 씀)
│   │   ├── World/
│   │   │   ├── Geometry.swift         # ScreenArea, WindowSnapshot, Ledge, Wall, 구간 연산
│   │   │   ├── World.swift            # 보이는 발판·벽·바닥·천장 계산과 질의
│   │   │   └── DesktopSource.swift    # 모니터·창 목록·맨 앞 앱을 주는 약속 (맥 SystemDesktop, 윈도우 WindowsDesktop)
│   │   ├── Habitat/
│   │   │   ├── HabitatLoop.swift      # 60Hz 한 틱의 순서: 창 갱신(움직이면 빠르게) → 펫 진행 → 그리기 → 마우스 받을 무대
│   │   │   ├── HostContracts.swift    # 껍데기가 주는 것: HostSenses(포인터·쉰 시간·키 수·마이크), PetStage(무대)
│   │   │   └── PetPointerGesture.swift # 누름·끌기·뗌·보조 누름 → 쓰다듬기·집기·던지기·펫 메뉴·물건 클릭
│   │   ├── Stage/
│   │   │   ├── SceneComposer.swift    # 펫·무기·물건 → 그리기 목록 (발 맞춤·반전 보정·말풍선 숨김·모자·발자국)
│   │   │   └── SceneDrawings.swift    # PetDrawing<Frame>, ProjectileDrawing, ItemDrawing
│   │   ├── Settings/
│   │   │   ├── PetSettings.swift      # 설정 항목·기본값·허용 값 (펫 고유 ID petIDs 포함)
│   │   │   └── SettingsStore.swift    # 저장소 약속 + JSON 파일 저장소(윈도우 %APPDATA%\DeskPet\settings.json)
│   │   ├── App/
│   │   │   ├── AppMenu.swift          # 메뉴바(트레이) 메뉴 데이터와 설정 명령 처리, 껍데기 약속 AppMenuHost
│   │   │   ├── PetLineup.swift        # 펫마다 캐릭터: 복원·추가·빼기·바꾸기, 우클릭·메뉴바 메뉴 데이터
│   │   │   └── CollectionMenu.swift   # 도감 메뉴, 펫 메뉴(레벨·모자·손 소품·이름·빼기 확인), 주운 물건 넣기, 도감 저장(TreasuryStore + TreasuryArchive)
│   │   ├── Pet/
│   │   │   ├── Pet.swift              # 펫 몸(발 위치·방향·딛는 면), 현재 행동, 말풍선, 클릭·알림 수신
│   │   │   ├── PetBehavior.swift      # 행동 프로토콜(클릭·알림 반응 포함), 땅 위 공통 반응, 물리 상수
│   │   │   ├── Behaviors/             # Idle, Walk, Climb, Airborne, Act, Dragged, Sleep, Glance(인사·돌아보기·구경), SkillLeap, Peek(최대화 창 거꾸로 빼꼼), ScreenHop(모니터 건너가기), Pounce·Throw(포인터에 뛰어오르기·무기 던지기, 정확도는 ThrowAim), CeilingWalk(창 아랫면 거꾸로 다니기), Tower(탑 맨 아래·머리로 뛰기·머리 위에 서기), Challenge(길 막은 펫에게 ⚔️ 결투 걸기), Entrance(메뉴바 밑에서 보는 창 위로 등장), Drumming(타이핑 따라 두드리기), Train(기관차·뒤 칸), CursorCarry(포인터 들고 달아나기), Fetch(물건 주우러 가기), Spin(Lv.2 한 바퀴)
│   │   │   ├── BehaviorPlanner.swift  # 다음 행동 선택(잠, 커서·친구 따라가기 포함), 등반 판단
│   │   │   ├── PetRoster.swift        # 펫 목록 소유, 진행, 일정마다 펫 배정(전령 등장·퇴장), 화면 밖 펫 복귀
│   │   │   ├── PetSocialCoordinator.swift # 펫끼리 마주치면 인사, 티격태격 대결(25%), 또는 올라타기 (짝별 20초 간격)
│   │   │   ├── PetTowerCoordinator.swift # 펫 탑: 올라타기 시작, 근처 펫이 맨 위로 (최대 4층)
│   │   │   ├── WindowShakeDetector.swift # 펫이 있는 창을 좌·우·좌로 흔들었는지 감지
│   │   │   ├── TypingCoordinator.swift # 타이핑 빠르기(TypingMeter), 따라 두드리기·🔥
│   │   │   ├── TrainCoordinator.swift # 기차놀이: 기관차 고르기, 가까운 순서로 줄 세우기
│   │   │   ├── CursorPrankCoordinator.swift # 포인터 장난: 잡기 조건, 쥔 자리, 사용자가 움직이면 돌려주기
│   │   │   ├── PersonalSpace.swift    # 겹치지 않기: 길 막은 펫 찾기, 겹친 펫 비켜 서기·밀어내기, 결투 받기
│   │   │   ├── SkillCoordinator.swift # 보고 있는 창이 바뀌면 이전 창의 펫은 바로, 아니면 한가한 펫 하나를 스킬 도약시킴 (30초 간격)
│   │   │   ├── FocusShift.swift       # 창이 바뀐 순간 알림(FocusTracker), 앱 종류 규칙표(AppCategory)
│   │   │   ├── ChaseMode.swift        # 쫓아다닐 것: 활성 창(ActiveWindowChase) / 마우스 포인터(PointerChase)
│   │   │   ├── Projectile.swift       # 닿지 않는 포인터에 던지는 무기(종류별 도트·궤적)
│   │   │   ├── ThrowAim.swift         # 던지기 정확도 단계(메뉴)·캐릭터 성격(aim)·빗나간 곳
│   │   │   ├── AttentionCoordinator.swift # 창을 바꾸면 쉬는 펫들이 돌아보고 앱 종류별 한마디
│   │   │   ├── WorkRhythmCoordinator.swift # 기지개·어지러움 한마디 (기본 꺼짐)
│   │   │   ├── DisplayFollowCoordinator.swift # 보고 있는 모니터로 나머지 펫이 8초에 한 마리씩 건너옴, 전령 등장 위치
│   │   │   ├── Vigor.swift            # Claude 사용량 → 기력 단계와 행동 배율
│   │   │   ├── LeapPlanner.swift      # 창 윗변에 올라서기·빼꼼 도약 속도 계산 (순수 계산)
│   │   │   ├── Speech.swift           # 말풍선(잡담·알림)과 반응 문구
│   │   │   └── RandomSource.swift     # 난수 주입 (검증용 고정 시드)
│   │   ├── Collection/
│   │   │   ├── ItemCatalog.swift      # 물건 12종(계절 2종): 이름(영·한), 8×8 도트, 비중, 나오는 달
│   │   │   ├── HatCatalog.swift       # 모자 8종(도트·조건)과 모자 자리 계산(HatPlacement)
│   │   │   ├── Affection.swift        # 친밀도 사건(PetMoment)·갈래와 상한(HeartSource)·적립과 레벨업(AffectionCoordinator)·손 소품 자리
│   │   │   ├── Treasury.swift         # 도감(개수·처음 찾은 날)·모자 얻기·펫별 모자와 저장 형식, 펫 고유 ID 맞추기(KeeperIDs)
│   │   │   ├── DroppedItem.swift      # 떨어진 물건 하나: 낙하·튐·창 따라가기·사라지기·메뉴바로 날아가기
│   │   │   └── FindingCoordinator.swift # 사용 시간 세기, 떨어뜨릴 때·곳, 줍는 펫 보내기, 클릭 처리
│   │   ├── Skin/
│   │   │   ├── PetSkin.swift          # 스프라이트 목록·애니메이션·방향별 프레임 선택 (그림 형식은 플랫폼이 정함)
│   │   │   ├── SkinLibrary.swift      # 스킨 폴더 탐색(SkinFolder)·전체 로드
│   │   │   ├── SpriteAlphaScanner.swift # RGBA 픽셀로 빈 프레임 판정, 몸 영역 측정
│   │   │   ├── HeadTracker.swift      # 프레임마다 머리 이동 측정(머리 본 맞추기). 모자가 머리를 따라감
│   │   │   └── PNGDecoder.swift       # 플랫폼 없이 PNG → RGBA 픽셀 (inflate 포함). 윈도우판 스킨 로더·맥 밖 검사용
│   │   ├── Schedule/
│   │   │   ├── ScheduleAnnouncer.swift   # 알릴 시점·문구 결정 (10분 전, 시작, 마감)
│   │   │   └── ScheduleWatcher.swift     # 30초마다 일정 확인 → 펫에게 전달
│   │   ├── Usage/ClaudeUsage.swift  # 사용량 파일(rate_limits) 해석, 지금 유효한 사용률
│   │   ├── Menu/
│   │   │   ├── MenuText.swift         # 메뉴 언어 선택과 메뉴 문구 (영어·한국어 쌍)
│   │   │   └── MenuNode.swift         # 메뉴 한 줄 데이터(MenuNode)·고른 일(MenuCommand)·대화 상자 약속(MenuDialogs)
│   │   └── Portable/
│   │       ├── PortableGeometry.swift # 맥은 CoreGraphics를 한 곳에서 들여오고, 그 밖에서는 CGVector를 보완
│   │       └── JSONNumber.swift       # JSON 숫자 읽기 (맥 NSNumber와 윈도우·리눅스 Int·Double 모두)
│   └── Mac/                       # macOS 껍데기 (AppKit·SpriteKit·EventKit·CoreAudio)
│       ├── main.swift
│       ├── App/
│       │   ├── AppController.swift    # 앱 수명주기, 공통 메뉴(AppMenu)를 메뉴바(👾)에 띄움, 껍데기 쪽 설정 적용(AppMenuHost)
│       │   ├── Habitat.swift          # HabitatLoop를 60Hz 타이머·화면 변경 알림에 연결, MacHostSenses
│       │   ├── PetDragInput.swift     # NSEvent → PetPointerGesture (control 클릭은 보조 누름)
│       │   ├── MacMenuRenderer.swift  # MenuNode → NSMenu, NSAlert 대화 상자(MacMenuDialogs)
│       │   ├── UserDefaultsSettingsStore.swift # 설정을 UserDefaults에 (예전 키 그대로)
│       │   ├── UserDefaultsTreasuryArchive.swift # 도감을 UserDefaults treasury.v1에, 읽지 못하면 treasury.broken으로
│       │   ├── PetLogger.swift        # 백그라운드 큐 파일 로거
│       │   ├── MicrophoneMonitor.swift # 마이크 사용 중인지(통화 중) 확인, 소리는 읽지 않음
│       │   ├── KeyPressCounter.swift  # 키 누름 횟수만 셈 (어떤 키인지·내용은 모름)
│       │   ├── CursorMover.swift      # 펫이 쥔 포인터를 옮김 (Pointer Pranks 켰을 때만)
│       │   └── ClaudeUsageWatcher.swift # 상태줄이 남긴 Claude 사용량 파일을 30초마다 읽음
│       ├── World/SystemDesktop.swift # macOS 모니터·창 목록·맨 앞 앱 읽기 (Quartz → Cocoa 좌표)
│       ├── Schedule/EventKitScheduleSource.swift # 맥 캘린더·미리 알림 읽기, 권한 요청
│       ├── Skin/MacSprites.swift  # PNG → SpriteKit 텍스처와 픽셀 (MacSkin, MacPetDrawing)
│       └── Stage/
│           ├── ScreenStage.swift      # 모니터별 투명 패널, 스프라이트, 말풍선
│           ├── SpeechBubbleNode.swift # 말풍선 모양 (잡담 흰색, 알림 노란색)
│           ├── SkillTrailNode.swift   # 스킬 도약 입자 (흙먼지, 불꽃, 칼바람)
│           ├── DotArt.swift           # 텍스트 도트 → 텍스처·메뉴 아이콘
│           └── StageDirector.swift    # 모니터 구성에 맞춰 무대 관리, 공통 그리기 목록을 무대에 넘김 (PetStage)
│   └── Windows/                   # 윈도우 껍데기 (Win32, 2단계 진행 중). 맥 밖에서만 컴파일
│       ├── main.swift                 # DPI 인식, 숨은 최상위 창, 틱·메시지를 함께 기다리는 루프
│       ├── App/
│       │   ├── WindowsApp.swift       # 공통 조각 연결, 60Hz 진행, 트레이 명령, 껍데기 쪽 설정, --smoke 보고서
│       │   ├── FrameTimer.swift       # 고해상도 대기 타이머 (SetTimer는 31ms로 늘어남)
│       │   ├── WindowsHostSenses.swift # GetCursorPos·GetLastInputInfo·SetCursorPos (키 수·마이크는 4단계)
│       │   └── WindowsStorage.swift   # %APPDATA%\DeskPet(설정·도감), %LOCALAPPDATA%\DeskPet\Logs, DESKPET_DATA_DIR
│       ├── World/
│       │   ├── WindowsDesktop.swift   # EnumDisplayMonitors(작업 영역)·EnumWindows + DWM 프레임·맨 앞 앱
│       │   └── WindowsCoordinates.swift # 가상 화면(왼쪽 위, 아래 +y) ↔ 공통 좌표(왼쪽 아래, 위 +y)
│       ├── Menu/TrayMenu.swift        # 트레이 아이콘, MenuNode → HMENU, 메시지 상자 대화(이름 입력은 3단계)
│       ├── Skin/WinSprite.swift       # PNGDecoder → 미리 곱한 BGRA
│       └── Stage/HeadlessStage.swift  # 2c 전까지: 그리기 목록만 만들고 화면에는 안 그림
├── Assets/Skins/                  # 캐릭터 23종 (공개 19종 + 로컬 전용 Boy·Girl·Goblin·Radish), Nabi·Bolt는 SpriteForge 생성물
├── Assets/Rigs/                   # SpriteForge 원본: 리그(<이름>.rig.json), 원본 스킨 매달리기(<스킨>.hang.json), 시트 가져오기(<이름>.import.json)
├── Assets/Sources/                # 가져온 무료 에셋 원본 줄 PNG와 출처·라이선스 메모 (PixelAdventure1, SunnyLand, NinjaAdventure, DungeonTilesetII)
├── Tools/SpriteForge/             # 캐릭터 제작 도구: 리그 → 모든 동작 프레임, 이미지 → 도트 초안 (생성 모델 호출 없음)
├── .claude/skills/deskpet-sprite/ # 에이전트용 캐릭터 제작 스킬 (sprite-gen 기조, 추가 구독·API 없음)
├── scripts/
│   ├── package_app.sh             # Release 빌드, ad-hoc 서명, DeskPet.app·.dmg·.zip 생성 (기본 공개용, --with-private)
│   ├── verify.sh                  # Core 홀로 컴파일·맥 전용 import 금지 확인 + 모델 검증 실행 (맥 밖에서는 공통 코드와 검사만)
│   └── checks/                    # 검증 시나리오 (스킨, 월드, 행동, 장시간 무작위, 잠·클릭·인사·일정). MacSkinChecks만 맥 전용
├── .github/workflows/core-portability.yml # Windows(DeskPet.exe 빌드·검사·연기 시험)·Linux(Core 빌드·검사)
├── install.sh                     # 터미널 한 줄 설치·지우기 (Releases의 DeskPet.zip)
├── Package.swift
└── run.sh                         # DeskPet.app 실행
```

---

## 3. 동작 흐름

1. `AppController`가 스킨을 읽고 저장된 설정으로 펫을 만든 뒤 `Habitat`을 시작한다.
2. `Habitat`의 60Hz 타이머가 매 틱:
   - 0.1초마다(창이 움직이는 동안은 1/30초마다) `SystemDesktop`에서 창 목록을 읽어 `World`를 갱신 (보이는 발판·벽 재계산)
   - 1초마다 마이크 사용 여부로 통화 중인지 확인 (`roster.isQuiet`)
   - `PetRoster`가 각 펫의 현재 행동을 진행 (행동이 다음 행동을 돌려주면 전환), 마주친 펫끼리 인사, 창이 바뀌면 스킬 도약·돌아보기·작업 리듬, 대기 중인 일정 알림 전달
   - `StageDirector`가 펫과 말풍선을 걸쳐 있는 모니터 무대에 그림
   - 커서가 펫 위면 그 무대만 클릭을 받게 함
3. 모니터 구성이 바뀌면 `World`와 무대만 다시 만든다. 펫은 `PetRoster`에 그대로 있다.
4. `ScheduleWatcher`가 30초마다(캘린더 변경 시 즉시) 일정을 읽고, `ScheduleAnnouncer`가 고른 문구를 `PetRoster.announce`로 넘긴다.

### 일정 말풍선 참고
* 처음 실행 때 macOS가 캘린더·미리 알림 접근을 묻는다. 거부했다면 메뉴 **Allow Calendar Access…**로 시스템 설정을 열어 허용.
* 다른 앱의 알림 센터 내용은 읽지 않는다. Outlook·Google 일정은 시스템 설정 → 인터넷 계정에 추가돼 있어야 잡힌다.
* 권한 설명 문구가 Info.plist에 있어야 해서 `swift build`로 만든 실행 파일을 직접 실행하면 일정 기능은 꺼진다. `./scripts/package_app.sh`로 만든 `DeskPet.app`에서만 동작.
* LLM을 쓰지 않는다. 문구는 정해진 짧은 틀(`10분 뒤 · 제목`, `지금 · 제목`, `할 일 · 제목`)로 만든다.
* 알림 배분(`PetRoster`): 빈손 기본 펫 → 전령 펫(최대 4, 기본 펫과 다른 스킨을 돌아가며) → 대기 줄. 확인하지 않은 같은 일정의 다음 알림은 같은 펫의 문구만 바꾼다. 전령은 펫 수 설정·스킨 교체·펫 삭제 대상이 아니다.
* 앱을 다시 빌드하면(임시 서명이라 macOS가 새 앱으로 봄) 캘린더 접근을 다시 묻는다. 설치한 DMG를 계속 쓰면 처음 한 번만 묻는다.
* 알림을 띄울 때 로그(`📅 queued notice`)에 일정 제목이 함께 남는다.
* 통화 중(마이크 사용 중)에는 일정 말풍선이 제목 없이 보인다. 메뉴 **Quiet During Calls**로 끌 수 있다.

### 캐릭터 고르기 참고
* 펫을 **우클릭**(또는 control 클릭)하면 그 펫의 캐릭터를 바꾸거나 뺄 수 있다(`PetLineup`).
* 메뉴바 👾: **Pets**(펫별 캐릭터·빼기), **Add Pet**(캐릭터를 골라 추가), **Add Another Pet (+)**(아직 없는 캐릭터 우선), **All Pets As**(모두 같은 캐릭터로).
* 펫별 캐릭터는 순서대로 저장돼 다시 실행해도 유지된다(`petSkins`). 예전 설정(한 캐릭터 × 펫 수)은 자동으로 이어받는다.
* 전령 펫은 기본 펫들이 입지 않은 캐릭터를 돌아가며 쓴다.

### Claude 사용량 참고
* `~/.claude/statusline-command.sh`에 추가한 몇 줄이 상태줄 갱신 때마다 공식 `rate_limits`만 `~/Library/Application Support/DeskPet/claude-usage.json`에 쓴다. 원본 백업: `~/.claude/statusline-command.sh.bak-deskpet`. 되돌리려면 백업으로 덮어쓰면 된다.
* 사용률 50%부터 펫이 느려지고, 80%부터 점프·도약·대결을 안 하며, 95%부터 누워서 🪫. 한도가 초기화되면 ⚡ 하고 일어남. 메뉴 **Tire With Claude Usage**.
* Pro·Max 구독이 아니거나 Claude Code를 아직 안 썼으면 파일이 없어 평소대로 움직인다.

### 쫓아다니기 참고
* 메뉴 **Chase ▸ Mouse Pointer**를 고르면 펫들이 활성 창 대신 마우스 포인터를 쫓는다. 포인터 아래 바닥으로 걸어오고(멀면 뜀), 포인터를 창 윗변 위에 0.6초 두면 그 창으로 도약하며, 메뉴바에 두면 최대화 창에서 빼꼼한다. 포인터 곁에 오면 대부분 그 자리에서 바라본다. 포인터가 머리 위 높은 곳이면 뛰어올라 닿으려 하고(닿으면 ✨), 못 닿으면 캐릭터별 무기(몽둥이·불꽃·칼·돌멩이)를 던진다(로그 `🎯 ... threw`).
* 포인터가 다른 모니터에 5초 머물면 나머지 펫도 그 모니터로 건너온다. 앱 반응(돌아보기·💬 등 한마디)은 모드와 상관없이 실제로 보는 창 기준. 기본은 **Active Window**.

### 창 아랫면 참고
* 펫이 가끔 창 아랫변으로 뛰어올라 거꾸로 붙어 다닌다(머리 위 가까이에 창 아랫변이 있을 때, 9초 정도). 포인터 모드에서는 포인터를 창 바로 밑에 두면 그 아랫변에 붙어 포인터 위로 온다. 클릭하면 떨어진다. 로그 `🦘 ... (cling)`, 행동 이름 `clinging`.
* 바닥(Dock)과 60pt 안쪽인 창 아랫변, 다른 창에 가린 부분은 쓰지 않는다. Skill Jumps를 끄면 가지 않는다.

### 창 흔들기·펫 탑 참고
* 펫이 올라탄 창을 잡고 좌·우·좌로 빠르게(1.5초 안, 한 번에 40pt 넘게) 흔들면 펫들이 튕겨 나간다. 로그 `🫨 window … shaken`, 행동 이름 `flung` → `dizzy`. 창 아랫변에 붙은 펫, 빼꼼 중인 펫도 떨어진다.
* 같은 발판의 펫 둘이 마주치면 가끔 한 마리가 머리에 올라탄다(로그 `🗼 … hops onto`). 근처 펫이 더 올라와 최대 4층(`🗼 … climbs onto`). 8초쯤(올라올 때마다 4초 더, 최대 18초) 뒤 무너진다. 아래 펫을 클릭하면 바로 무너지고, 위 펫을 클릭하면 그 펫만 뛰어내린다.
* 펫이 많을수록 자주 쌓는다. 확률은 `PetSocialCoordinator.piggybackChance`(0.35), `PetTowerCoordinator.joinRate`(초당 0.5).

### 겹치지 않기 참고
* 걷다가 앞 펫에 막히면 그 앞에서 멈추고, 뛰어넘거나(`leapfrogging`), ⚔️ 결투를 걸거나(`challenging` → 받으면 `sparring`, 로그 `⚔️ … duels … to pass`), 돌아선다. 자는 펫은 깨우지 않고 뛰어넘는다.
* 포인터·친구 쪽으로 모일 때는 목적지가 앞 펫 바로 옆이면 그 옆에 선다. 그래서 여러 마리가 나란히 줄 선다.
* 겹쳐 내려앉으면 옆 빈자리로 비킨다(로그 `↔️ … makes room`). 자리가 없으면 서로 천천히 밀어낸다.
* 같은 쪽으로 가는 펫 뒤에서는 넘지 않고 기다리고, 포인터를 쫓다 막히면 그 자리에 멈춰 바라보기도 한다(2026-11-19 빈도 조정).
* 비중: 뛰어넘기 `BehaviorPlanner.leapfrogWeight`(5), 결투 `duelWeight`(3), 돌아서기 `turnBackWeight`(2), 멈춰 바라보기 `settleWeight`(9). 서둘 때 바로 뛰어넘기 `hurriedLeapChance`(0.5), 서 있는 무리 곁 멈춤 거리 `crowdSlack`(110).

### 등장 연출 참고
* 로그 `entering ➔ droppingIn` → `droppingIn ➔ greetingUser`. 간격은 `EntranceBehavior.firstDelay`(0.6초), `stagger`(0.45초), 자리 간격 `spacing`(70pt).
* 보는 창 윗변이 메뉴바 가까이면 떨어지는 거리가 짧다. 최대화 창이나 보는 창이 없으면 바닥에 내려앉는다.

### 타이핑 반응 참고
* 로그 `⌨️ [Pet-n] drums along (6/s)`, `🔥 … fast typing`. 앱을 켤 때 `⌨️ key-press counter starts at N`이 0이 아니면 횟수를 읽을 수 있는 것.
* 키 내용·어느 키인지는 읽지 않는다. 권한 창 없이 동작했다(2026-11-19, 이 맥 기준). 만약 macOS가 입력 모니터링 권한을 물으면 거부해도 다른 기능에는 영향이 없다(횟수가 늘지 않아 반응만 안 함).
* 기준값: `TypingCoordinator.joinRate`(초당 3), `joinChance`(0.15), `fireRate`(초당 8), `DrummingBehavior.normalRate`(6).

### 기차놀이 참고
* 로그 `🚂 [Pet-n] leads Pet-a, Pet-b east`, 행동 이름 `trainLeading`·`trainRiding`. 펫 둘 이상이 같은 발판에서 쉬고 있어야 한다(1분에 한 번까지).
* 자주·드물게 하려면 `TrainCoordinator.startChance`(초당 0.04), `cooldown`(60초).

### 포인터 장난 참고
* 메뉴 **Pointer Pranks**(기본 꺼짐). 펫 몸 가까이에 포인터를 2초 두면 가끔(50%, 2분에 한 번) 잡아 1초쯤 들고 달린다. 마우스를 조금만 움직여도 바로 돌려준다. 로그 `😆 … snatched the pointer`, `✋ … pointer taken back`.
* 처음 옮길 때 로그에 `🖱️ pointer move works`가 남으면 권한 없이 동작하는 것. `failed`면 macOS 손쉬운 사용 권한이 필요한 환경이다(이 기능만 안 됨).

### 물건 줍기 참고
* 사용 중 시간만 세며, 켠 뒤 3~8분에 첫 물건, 그다음 6~18분마다 하나. 입력이 5분 없거나 통화 중이면 시계가 멈춘다.
* 같은 발판 펫이 없으면 30초 뒤 다른 발판 펫이 도약하거나(Skill Jumps 켜짐) 걸어 내려온다. 3분 안에 못 주우면 사라진다.
* 로그 `🎁 dropped`, `✨ […] picked up … after Ns`, `🍂 … faded away`. 켤 때 `🎒 collection: N items`.
* 도감은 UserDefaults `treasury.v1`. 읽을 수 없으면 `treasury.broken`으로 옮기고 새로 시작. 메뉴 **Reset Collection…**으로 지움(확인 창).
* 모자: 얻으면 주운 펫이 🎩, 모자가 없던 펫은 바로 씀. 자리가 어긋난 스킨은 `.import.json`의 `hatAnchor`로 맞추고 `swift run SpriteForge import`로 다시 만듦(지금 Opossum만). 로그 `🎩 unlocked`, `🎩 [Pet-n] wears`.
* 친밀도: 하루 상한 함께 16·쓰다듬기 10·인사 1·활약 5(줍기 +2는 무제한). 레벨 경계 10/30/60/100/150. Lv.2 이상 펫을 빼면 확인 창. 로그 `💗 [Pet-n] reached Lv.N`.
* 계절 물건: 그 맥의 달 기준(북반구). 기간이 아니면 나오지 않고, 도감에 기간이 보인다.
* 기획 전체와 단계별 구현 기록은 `Controller/COLLECTION_PLAN.md`(14~17절).

### 창 바꾸기 참고
* 최대화 창에서 빼꼼하던 펫은 다른 최대화 창으로 바꾸면 그 창으로 옮겨 간다. 높이가 다른 창이면 30초 대기 없이 건너간다.
* 펫들은 창을 바꾸지 않아도 보고 있는 창으로 자주(다음 행동을 고를 때 약 20%) 스킬 도약해 올라간다. 한 창에 3마리까지.
* 쉬던 펫들은 새 창 쪽을 돌아보고(15초에 한 번), 메신저 💬·메일 📨·영상 🍿·개발 도구 ⌨️ 앱이면 한마디 한다(종류별 1분에 한 번). 번들 ID 규칙표 `AppCategory.rules`로 관리.
* 펫끼리 마주치면 25%는 인사 대신 티격태격(3번 주고받기, 💥, ✌️/🏳️). 클릭하면 멈춤.
* **Break Reminders**를 켜면 50분 연속 사용 시 `기지개 🙆`, 창을 너무 자주 바꾸면 `😵`.
* 보고 있는 창이 펫이 없는 다른 모니터에 있으면 펫 하나가 스킬 효과와 함께 사라졌다 그 모니터 바닥에 나타나고, 이어서 창으로 도약한다. 로그 `🌀 ... → display`.
* 그 모니터에 5초 머물면 나머지 펫도 8초에 한 마리씩 건너온다(로그 `🌀 ... following to display`). 새 전령 펫도 그 모니터에 나타난다. 메뉴 **Follow To Display**로 끔.

---

## 4. 빌드·실행·검증

```bash
# 모델 검증 (스킨 로드, 월드, 행동 시나리오, 시뮬레이션 10분 무작위 진행)
./scripts/verify.sh

# 릴리스 빌드 + DeskPet.app + DeskPet.dmg
./scripts/package_app.sh

# 실행 (메뉴바 👾)
./run.sh

# 로그 보기
tail -f ~/Library/Logs/DeskPet/pet_debug.log
```

* 릴리스 올리기: `./scripts/package_app.sh` 뒤 GitHub Releases에 `DeskPet.dmg`와 `DeskPet.zip`을 함께 올린다. 터미널 한 줄 설치(`install.sh`)는 `releases/latest/download/DeskPet.zip`을 받으므로 파일 이름을 바꾸지 않는다.
  * 앱 묶음은 ad-hoc 서명(공증 없음). curl로 받은 파일에는 격리 표시가 없어 바로 열리고, 브라우저로 받은 DMG는 처음 한 번 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 그래도 열기가 필요하다.
  * `install.sh` 시험: `DESKPET_URL=file://$PWD/DeskPet.zip DESKPET_DIR=/tmp/x DESKPET_NO_LAUNCH=1 bash install.sh` (지우기는 `--uninstall`).
* 공개 배포: `./scripts/package_app.sh`는 `scripts/private-skins.txt`의 캐릭터(Boy·Girl·Goblin·Radish, 출처·재배포 허락 미확인)를 빼고 만든다. 이 4종은 저장소에서도 추적하지 않고(`.gitignore`) 로컬에만 둔다. 개인용으로 모두 넣으려면 `--with-private`(DMG도 그 구성으로 덮어씀).
* 종료: 메뉴바 `👾` → **Quit DeskPet**(한국어 메뉴: **DeskPet 종료**), 또는 `pkill -f DeskPet`
* 윈도우 이식: `Controller/WINDOWS_PORT.md`. 0단계 완료 — 공통 코드는 `Sources/DeskPet/Core`(Foundation만), 맥 전용은 `Sources/DeskPet/Mac`. Core에 맥 전용 코드를 넣으면 `verify.sh`가 실패함
  * 1단계: GitHub Actions `Core portability`가 Windows·Linux에서 `swift build`(DeskPetCore)와 `scripts/verify.sh`를 돌린다. 맥 밖에서는 스킨을 공통 `PNGDecoder`로 읽고, SpriteForge 일치 검사는 건너뛴다.
  * 맥에서 윈도우와 같은 스킨 경로를 돌려 보려면 검사를 `-D PORTABLE_CHECKS`로 컴파일한다. 맥 검사는 `PNGDecoder`가 모든 스킨 PNG를 Core Graphics와 같은 픽셀로 읽는지도 확인한다.
  * 2a: 시계(`HabitatLoop`)·끌기 판정·설정·그리기 목록·메뉴 데이터가 Core에 있다. 맥 껍데기는 읽기(`DesktopSource`·`HostSenses`)·그리기(`PetStage`)·메뉴 렌더링·대화 상자·`UserDefaults`만 맡는다. 윈도우판은 같은 약속을 Win32로 구현한다(설계 명세 5.4).
  * 2b: 윈도우에서는 `swift build`가 `DeskPet.exe`(Core + Windows)를 만든다. CI 연기 시험은 메모장을 띄우고 `DeskPet.exe --smoke 8 --report smoke.json`을 돌려 모니터·창 목록·펫·트레이·틱 수를 확인한다(보고서와 로그는 아티팩트 `windows-smoke`). 아직 화면에 그리지 않는다(2c).
* XCTest는 Command Line Tools만 설치된 환경에서 쓸 수 없어 `scripts/checks/` 실행 파일로 검증한다. `swift build` 때 나오는 `could not determine XCTest paths` 경고는 같은 이유이며 빌드에 영향 없음.

---

## 5. 새 캐릭터(스킨) 추가

### 5.1 권장: 에이전트 스킬 `deskpet-sprite`
* Claude Code에서 "새 캐릭터 만들어줘"라고 하면 스킬이 안내한다. 에이전트가 부위별 도트를 그리고, `SpriteForge`가 걷기·대기·점프·매달리기·잠·공격 프레임을 코드로 만든다. 추가 구독·API 없음.
* 참고 그림이 필요하면 에이전트가 Gemini 앱에 붙일 문구를 주고, 저장한 이미지를 `SpriteForge pixelize`가 48px 도트 초안으로 바꾼다.
* 명령:
  ```bash
  swift run SpriteForge build Assets/Rigs/<이름>.rig.json --preview /tmp/<이름>.png
  swift run SpriteForge pixelize <이미지> --out Assets/Rigs/<이름>.rig.json
  ```
* 생성된 `Assets/Skins/<이름>/`은 손으로 고치지 않는다. `verify.sh`가 리그와 일치하는지 확인한다.
* 부위가 나뉘지 않은 원본 스킨에 매달리기를 더할 때:
  ```bash
  swift run SpriteForge hang Assets/Rigs/<스킨>.hang.json --preview /tmp/<스킨>_hang.png
  ```
  `.hang.json`에는 바탕 이미지와 팔 사각형만 적는다(설계 문서 8절).
* 무료 에셋 시트를 스킨으로 바꿀 때:
  ```bash
  swift run SpriteForge import Assets/Rigs/<이름>.import.json --preview /tmp/<이름>.png
  ```
  원본 줄 PNG와 `SOURCE.md`(출처·라이선스)를 `Assets/Sources/<팩>/`에 둔다. 재배포가 막힌 라이선스나 변경 금지(ND) 에셋은 넣지 않는다.

### 5.3 출처 표시
* NinjaFrog·MaskDude·PinkMan·VirtualGuy: "Pixel Adventure" by Pixel Frog — https://pixelfrog-assets.itch.io/pixel-adventure-1 (CC0 1.0, 제작자의 OpenGameArt 게시본은 CC-BY 4.0이라 출처를 함께 표시)
* Foxy·Opossum·Froggy: "Sunny Land" by Luis Zuno (ansimuz) — https://ansimuz.itch.io/sunny-land-pixel-game-art (CC0 1.0, 팩 안 `public-license.pdf`로도 확인)
* Elf·Wizard·Lizard·Dwarf·BigDemon: "16x16 DungeonTileset II" by 0x72 — https://0x72.itch.io/dungeontileset-ii (CC0 1.0)
* NinjaGreen·Skeleton·Samurai·Princess·Knight: "Ninja Adventure" by Pixel-boy and AAA — https://pixel-boy.itch.io/ninja-adventure-asset-pack (CC0 1.0, 팩의 `LICENSE.txt`를 `Assets/Sources/NinjaAdventure/`에 복사)

### 5.2 직접 넣기 (기존 시트·외부 도구)

1. `Assets/Skins/<이름>/`에 48x48 PNG들과 `metadata.json`을 둔다.
   ```json
   {
     "states": [
       {
         "frames": {
           "rotations": { "south": "rotations/south.png", "east": "rotations/east.png", "west": "rotations/west.png", "north": "rotations/north.png" },
           "animations": {
             "Walking": { "east": ["animations/Walking/east/frame_000.png", "..."], "north": ["..."], "south": ["..."] },
             "swing_attack": { "east": ["..."] }
           }
         }
       }
     ]
   }
   ```
2. 규칙
   * 걷기: 키에 `Walk` 또는 `Run`이 들어간 애니메이션. 등반은 걷기의 `north`를 씀.
   * 공격(선택): 키에 `attack` 또는 `swing`이 들어간 애니메이션. 없으면 공격 행동을 고르지 않음.
   * 서쪽 이미지가 없으면 동쪽 이미지를 좌우 반전해 씀. 있으면 그대로 씀.
   * **방향 이름은 이미지가 실제로 보는 방향과 같아야 함.** 한쪽만 그려진 시트는 그 방향만 적으면 반대쪽은 반전으로 만듦 (Boy·Girl은 `west`만 있음).
   * 등반은 걷기의 `north`(뒷모습)를 쓰고, 없으면 벽 쪽을 향한 걷기로 오름.
   * 스킬(선택): 최상위에 `"deskpet": {"skill": "pole_vault" | "flame_rocket" | "slash_jump" | "big_jump"}`. 없으면 `big_jump`.
   * 시트를 자르며 생긴 빈 칸(픽셀 없는 PNG)은 자동으로 건너뜀. 개수는 로그의 `📦 Loaded skin asset` 줄에 남음.
   * 몸 크기와 발 위치는 대기(rotations) 이미지의 보이는 영역으로 자동 측정.
3. `./scripts/verify.sh`로 방향별 프레임 수와 몸 크기를 확인하고, 앱을 다시 실행하면 펫 우클릭 메뉴와 **Pets**·**Add Pet**·**All Pets As** 메뉴에 나타난다. 앱 번들에 넣으려면 `./scripts/package_app.sh`를 다시 실행.

---

## 6. 문제 해결 이력

| 문제 현상 | 원인 | 해결 |
| :--- | :--- | :--- |
| Spaces 전환 때만 잠깐 보이고 사라짐 | `screenSaverWindow` 레벨이 전환 완료 시 렌더링 차단됨 | `statusBar` 레벨 + `activeSpaceDidChange` 때 전면화 |
| 듀얼 모니터에서 계속 위로만 올라감 | 위 모니터 창 좌표가 다른 모니터로 잘못 매핑됨 | 전역 좌표 하나로 통일 (재작성) |
| 도트 애니메이션이 굳음 | 백그라운드에서 `SKAction` 정지 | 시간 기반 프레임 선택, 단일 60Hz 타이머 |
| 크기가 바뀌거나 떨림 | 텍스처 교체 시 크기 리셋 | 매 틱 크기·위치를 명시적으로 지정, 픽셀 격자 맞춤 |
| Boy·Girl이 걷거나 오를 때 깜빡임 | 시트 분할로 생긴 투명 프레임(스킨당 7개) | 로드 단계에서 빈 프레임 제외 |
| 화면 구성이 바뀌면 펫이 사라짐 | 화면별 장면이 펫을 소유하고 재구성 때 버림 | 펫은 `PetRoster` 소유, 무대만 재생성 |
| App Nap 방지가 동작하지 않음 | 활동 토큰을 보관하지 않아 즉시 해제 | 토큰 보관, 자동 잠자기는 허용하는 옵션으로 변경 |
| 창 꼭대기에 닿자마자 떨어짐 | 올라선 x가 창 바깥에 남음, 방향 반대 | 지붕 안쪽으로 올라서고 안쪽 방향으로 걸음 |
| 높은 창을 끝까지 못 오름 | 15초 제한·천장 클램프 | 시간 제한 제거, 머리 공간 없는 창은 처음부터 오르지 않음 |
| 공격 동작에서 멈춤 (Boy·Girl·Radish) | 공격 프레임이 없는데 공격 상태로 들어감 | 공격 애니메이션이 있는 스킨만 공격 선택, 시간으로 종료 |
| 서쪽을 볼 때 대기 자세가 반대쪽을 봄 | 서쪽 이미지에 좌우 반전을 한 번 더 적용 | 서쪽 이미지가 없을 때만 반전 |
| 창이 움직여도 허공을 걷거나 앞 창 한가운데에 섬 | 옛 창 위치 기억, 가림 무시 | 창 ID로 추적, 보이는 면만 발판·벽 |
| 배포본에서 로그가 안 남음 | 로그 경로가 개발 폴더로 고정 | `~/Library/Logs/DeskPet/`로 변경 |
| Boy·Girl이 오른쪽으로 갈 때 뒷걸음질, 왼쪽으로는 미끄러지듯 이동, 등반 중 칼질 효과 | 원본 시트는 모두 왼쪽을 보는 단일 방향이고 줄마다 다른 동작인데, 줄을 방향으로 잘못 나눔 | 실제 동작별로 다시 정리(`Walking`·`swing_attack`·`Idle`·`Blink`의 `west`), 오른쪽은 반전. 공격 애니메이션도 생김 |
| 창이 최대화·모니터 이동하면 펫이 화면 밖으로 끌려감 | 창 이동량을 그대로 따라감 | 0.1초에 250pt 넘게 움직이거나 따라가면 화면 밖이면 타지 않고 그 자리에서 낙하 (서 있을 때·오를 때 모두) |
| 머리 큰 캐릭터가 매달릴 때 얼굴에 팔이 겹치거나 머리로 매달린 것처럼 보임 | 위로 든 팔이 머리 앞에 그려지고 머리보다 짧음 | 매달리기·점프에서 팔은 머리 뒤에 그리고 손끝이 머리 위·귀 사이로 나오게 늘림 (SpriteForge) |
| 위에 모니터를 연결하면 최대화 창 윗변에 올라서 메뉴바를 가릴 수 있음 | 천장을 x 위치의 가장 높은 모니터 윗변으로 계산 | 천장은 지금 높이가 속한 사용 가능 영역의 윗변. 메뉴바에서 끊김 |
| 다른 앱으로 바꾸면 매달려 있던 펫이 쫓겨나듯 떨어지고, 30초 안이면 아무도 새 창으로 안 감 | 가려지면 무조건 낙하, 도약은 대기 시간만 봄 | 같은 높이 윗변이면 옮겨 잡기, 이전 창의 펫은 대기 없이 따라가기 |
| 위 모니터에 있던 펫이 모두 아래로 떨어져 다시 못 올라감, 위 모니터 창을 봐도 아무도 안 감 | 위 모니터 바닥이 아래 모니터와 맞닿은 구간에서 뚫려 있고, 메뉴바 천장 때문에 올라갈 수 없음 | 위 모니터 바닥을 막고, 펫 없는 모니터의 창을 보면 건너가기 |
| Boy·Girl·Goblin·Radish가 매달릴 때 정지 이미지 한 장 | 원본 스킨에 `Hang` 동작이 없음 | `SpriteForge hang`으로 팔을 들어 올린 4프레임 추가 |
| 창에 매달린 모습이 부자연스러움 (팔이 귀처럼 보임, 가져온 캐릭터는 떨어지기·대기 그림, 몸이 창 윗부분을 가림) | 캐릭터마다 매달리기 그림 품질이 제각각 | 매달리기를 **거꾸로 빼꼼**으로 바꿈: 윗변 뒤로 숨었다가 대기 프레임을 뒤집어 머리만 내밂. 무대가 자세대로 잘라 그려 모든 스킨에 같은 방식 (2026-11-18) |

---

## 7. 참고
* 설계 원칙: [`Controller/DESKTOP_PET_CONTROLLER.md`](Controller/DESKTOP_PET_CONTROLLER.md) (코드 수정 전 선행 갱신)
* 본 문서는 루트와 `Controller/`에 같은 내용으로 두 곳 있음. 수정 시 함께 갱신.
