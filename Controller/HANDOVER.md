# DeskPet 프로젝트 인수인계 및 운영 핸드오버 문서 (Handover Document)

본 문서는 macOS 상주형 데스크톱 펫 애플리케이션 **DeskPet**의 아키텍처, 핵심 알고리즘, 빌드/배포 절차, 신규 애셋 추가 가이드 및 트러블슈팅 이력을 정리한 완성형 인수인계 문서입니다.

---

## 1. 프로젝트 개요 (Executive Summary)

* **프로젝트명:** DeskPet (macOS Desktop Screenmate Companion)
* **언어 및 플랫폼:** Swift 5.9, macOS 13.0+ (Apple Silicon arm64 / Intel)
* **주요 프레임워크:**
  * **UI & 시스템 윈도우:** AppKit (`NSPanel`, `NSStatusBar`, `NSWorkspace`)
  * **렌더링 & 픽셀 물리:** SpriteKit (`SKView`, `SKScene`, `SKNode`)
  * **윈도우 감지:** Quartz Window Services / CoreGraphics (`CGWindowListCopyWindowInfo`)
* **핵심 기능:**
  1. **완전 마우스 관통 (Pass-Through):** 작업 중인 에디터/브라우저의 클릭·타이핑에 0.001%도 방해 없음 (`ignoresMouseEvents = true`).
  2. **스마트 드래그앤드롭:** 마우스로 캐릭터 몸체를 콕 집으면 공중에 대롱대롱 들려 옮길 수 있고 놓으면 중력 낙하.
  3. **마우스 포인터 추종 (Mouse Following):** 마우스 커서의 위치를 호기심 어린 눈으로 감지하여 아장아장 다가옴.
  4. **듀얼/멀티 모니터 완벽 지원:** 맥북 내장 Retina + 외장 4K 모니터 각각에 독립 오버레이를 띄우고 모니터 간 자연스러운 워프/이동 지원.
  5. **실제 창 오브젝트 인식:** 열려 있는 창의 상단 타이틀바(발판)를 걷고, 창 세로 모서리(외벽)를 기어오르며, 낭떠러지에서 다이빙 낙하.
  6. **절대 크기 보장 (Absolute Size):** 48x48 픽셀 크기가 흔들림 없이 고정되며, 0.11초 틱 프레임 애니메이션 상시 구동.
  7. **실시간 디버그 로거:** 행동 및 좌표가 `pet_debug.log`에 실시간 flush 기록.

---

## 2. 시스템 아키텍처 및 파일 구조

```text
private/
├── Controller/
│   ├── DESKTOP_PET_CONTROLLER.md # 컨트롤러 도메인 명세서 (Documentation First Policy)
│   └── HANDOVER.md               # 본 인수인계 문서
├── Sources/
│   └── DeskPet/
│       ├── main.swift             # 앱 진입점
│       ├── AppController.swift    # 메뉴바(👾) 관리, App Nap 방지, 설정 조율
│       ├── OverlayController.swift# 멀티 모니터 오버레이 패널, Spaces 고정, 스마트 히트테스팅
│       ├── WindowObserver.swift   # Quartz 기반 창 감지 및 모니터별 좌표 정규화
│       ├── PetNode.swift          # FSM(10개 상태), 정밀 기하학 창 콜라이더, 수동 프레임 스테퍼
│       ├── PetScene.swift         # SpriteKit 투명 캔버스, 60fps 상시 물리 틱, 드래그앤드롭
│       ├── PetSkin.swift          # 48x48 스프라이트 시트 및 JSON 메타데이터 파서
│       └── PetLogger.swift        # 실시간 행동/좌표 파일 로거 (pet_debug.log)
├── Assets/
│   └── Skins/
│       ├── Goblin/                # 고블린 도트 애셋 (달리기, 공격, 방향별 컷)
│       └── Radish/                # 순무 도트 애셋 (걷기, 회전, 방향별 컷)
├── scripts/
│   └── package_app.sh             # Release 빌드 및 DeskPet.app 번들 패키징 스크립트
├── Package.swift                  # Swift Package Manager 매니페스트
├── run.sh                         # 간편 앱 실행 스크립트
└── pet_debug.log                  # 실시간 동작/좌표 로그 파일
```

---

## 3. 핵심 컴포넌트별 기술 명세

### 3.1 `OverlayController.swift` (화면 오버레이)
* **모니터별 독립 패널 생성 (`ScreenOverlay`):**
  * `NSScreen.screens`를 순회하며 모니터마다 1:1로 `NSPanel`과 `SKView`를 생성하여 해상도 차이(Retina vs 4K)를 완벽히 격리.
* **가상 데스크톱(Spaces) 상시 상주:**
  * `level = .statusBar` (25)
  * `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`
  * `activeSpaceDidChangeNotification` 옵저버로 스페이스 전환 시 즉시 전면 복귀.
* **스마트 마우스 히트테스팅:**
  * 0.05초 주기로 전역 마우스 위치를 감시하여 캐릭터 몸체 위로 커서가 오면 `ignoresMouseEvents = false`로 즉시 전환(클릭/드래그 허용), 벗어나면 `true` 복귀(100% 관통 유지).

### 3.2 `WindowObserver.swift` (창 인식)
* **Quartz ➔ Cocoa 로컬 좌표 정규화:**
  * Quartz의 음수/양수 혼합 Y 좌표를 Cocoa 전역 좌표로 1차 변환.
  * 각 모니터의 `screen.frame`과 교차하는 창만 필터링하여 **해당 모니터의 로컬 `(0, 0)` 기준 사각형(`CGRect`)으로 정규화** 전달.
  * 듀얼 모니터 환경에서 상단 모니터의 창 좌표가 하단 모니터로 잘못 들어가 위로만 올라가던 문제를 원천 차단.

### 3.3 `PetNode.swift` (물리 & 애니메이션 FSM)
* **10개 상태 머신(FSM):**
  * `idle`, `walking`, `climbing`, `sliding`, `jumping`, `falling`, `peek`, `action`, `mouseFollowing`, `dragged`
* **정밀 기하학 창 콜라이더 (Precise Geometric Colliders):**
  * **발판(Roof):** `win.maxY` 라인 (±10px), 수평 `[minX, maxX]`. 창 상단 타이틀바 착지 및 걷기.
  * **외벽(Wall):** 창의 왼쪽 외곽선(`abs(frontX - minX) <= 8`) 또는 오른쪽 외곽선(`abs(frontX - maxX) <= 8`). 벽에 닿았을 때만 등반.
  * **낭떠러지(Cliff):** 창 끝을 벗어나는 즉시 `falling` 전환 후 아래 창으로 낙하.
* **절대 크기 보장 (Absolute Size Architecture):**
  * `spriteNode.size = CGSize(width: 48 * scaleMultiplier, height: 48 * scaleMultiplier)`
  * `xScale = (currentDirection == .west) ? -1.0 : 1.0` (오직 방향 반전에만 사용)
  * 프레임 텍스처 변경 직후 크기 강제 잠금으로 크기 떨림 0% 보장.
* **독립 틱 프레임 스테퍼 (Manual Frame Stepper):**
  * 백그라운드에서 `SKAction`이 멈추는 문제를 해결하기 위해, `deltaTime` 기반으로 코드가 직접 0.11초마다 도트 프레임을 교체.

---

## 4. 빌드 및 실행 가이드

### 4.1 앱 번들 빌드 및 패키징
```bash
# 릴리즈 모드 컴파일 및 DeskPet.app 패키징
./scripts/package_app.sh
```

### 4.2 앱 실행
```bash
# 실행 스크립트 실행 (또는 Finder에서 DeskPet.app 더블 클릭)
./run.sh
```

### 4.3 앱 종료
* 맥OS 상단 메뉴바의 **`👾` 아이콘 ➔ [Quit DeskPet]** 클릭
* 또는 터미널: `pkill -f DeskPet`

### 4.4 실시간 로그 모니터링
```bash
# 실시간 행동 및 좌표 추적
tail -f pet_debug.log
```

---

## 5. 신규 캐릭터(스킨) 추가 가이드

앱을 다시 빌드하지 않고도 사용자가 폴더만 추가하면 새 캐릭터가 즉시 인식됩니다.

1. `Assets/Skins/<새로운캐릭터이름>/` 폴더 생성
2. 폴더 내에 48x48 스프라이트 PNG 파일들과 `metadata.json` 배치:
   ```json
   {
     "states": [
       {
         "frames": {
           "rotations": {
             "south": "rotations/south.png",
             "east": "rotations/east.png",
             "north": "rotations/north.png"
           },
           "animations": {
             "Walking": {
               "south": ["animations/Walking/south/frame_000.png", "..."],
               "east": ["animations/Walking/east/frame_000.png", "..."],
               "north": ["animations/Walking/north/frame_000.png", "..."]
             }
           }
         }
       }
     ]
   }
   ```
3. 앱 실행 시 메뉴바 `👾` ➔ **Character Skin** 목록에 자동으로 나타나며 클릭 즉시 교체됩니다.

---

## 6. 주요 트러블슈팅 및 해결 이력

| 문제 현상 | 원인 분석 | 적용된 해결책 |
| :--- | :--- | :--- |
| **데스크톱(Spaces) 넘길 때만 잠깐 보이고 사라짐** | `screenSaverWindow` 레벨이 스페이스 전환 완료 시 WindowServer에 의해 렌더링 차단됨 | `statusBar` (25) 레벨로 격상하고 `activeSpaceDidChange` 알림으로 상시 전면화 |
| **듀얼 모니터에서 계속 위로만 올라감** | 상단 삼성 4K 모니터(Y: -2160)의 창 좌표가 메인 모니터로 잘못 매핑되어 비정상적으로 높은 곳을 오르려 함 | 모니터별로 창 좌표를 로컬 `(0, 0)` 기준으로 격리 및 정규화 |
| **도트 움직임 애니메이션이 굳어 있음** | 백그라운드 윈도우에서 SpriteKit의 `SKAction` 타이머가 일시정지됨 | `SKAction`을 걷어내고 `deltaTime` 기반 독립 수동 프레임 스테퍼로 0.11초마다 강제 교체 |
| **크기가 제멋대로 바뀌거나 떨림** | 텍스처 교체 시 `SKSpriteNode.size`가 텍스처 기본값으로 리셋되고 `xScale`과 중복 곱셈됨 | `xScale`은 오직 좌우 반전(-1, +1)에만 쓰고 `size`를 48px 고정 크기로 강제 락 |
| **창을 오브젝트로 인식하지 못함** | 창 전체 사각형 내부를 벽으로 인식하여 창 한가운데를 지나갈 때도 벽으로 오인식 | 창 상단 타이틀바(발판)와 세로 외곽선(벽)만 정밀 기하학적으로 판정하도록 개선 |

---

## 7. 인수인계 담당자 안내
* **설계 명세 파일:** [`Controller/DESKTOP_PET_CONTROLLER.md`](file:///Users/HH191_1/Documents/private/Controller/DESKTOP_PET_CONTROLLER.md) (정책에 따라 코드 수정 시 본 명세를 선행 갱신해야 함)
* **로그 파일:** [`pet_debug.log`](file:///Users/HH191_1/Documents/private/pet_debug.log)
