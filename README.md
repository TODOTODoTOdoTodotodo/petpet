# DeskPet 👾

macOS 화면 위에 사는 도트 펫.
열어 둔 창 위를 걷고, 오르고, 뛰어내림. 마우스 포인터를 쫓아오고, 물건을 주워 모음.

<!-- 스크린샷·짧은 GIF 자리: 창 위를 걷는 펫, 창 흔들기, 펫 탑, 물건 줍기 -->

## 한눈에 보기

- **창이 곧 지형**
  - 지금 보이는 창의 윗변을 발판, 옆변을 벽으로 씀.
  - 창을 옮기면 펫도 같이 이동함. 창을 닫으면 펫이 떨어짐.
- **포인터를 아는 펫**
  - 메뉴 ▸ 따라갈 곳 ▸ 마우스 포인터로 바꾸면 포인터를 쫓아옴.
  - 닿지 않는 높이면 포인터 자리를 겨냥해 돌멩이·불꽃 등을 던짐. 가끔 빗나가면 😅.
- **창 흔들기**
  - 펫이 올라탄 창을 좌우로 흔들면 펫이 튕겨 나감. 착지 후 잠시 어지러움 💫.
- **펫끼리 놀기**
  - 인사, 티격태격, 펫 탑(최대 4층), 줄 서기 기차놀이.
- **줍고 모으고 키우기**
  - 일하는 동안 가끔 떨어지는 물건, 그것을 줍는 펫.
  - 도감, 모자 8종, 펫마다 쌓이는 친밀도(❤️ Lv.1~6).
- **캐릭터 19종**
  - 펫마다 다른 캐릭터 선택 가능, 최대 10마리.
- **내용은 보지 않음**
  - 키 입력은 횟수만, 창은 위치·크기만 사용.
  - 네트워크 연결 없음.

## 설치

**필요 환경**

- macOS 13 이상
- Apple Silicon Mac (M1 이후). Intel Mac 미지원.

**터미널 한 줄 설치 (추천)**

```bash
curl -fsSL https://raw.githubusercontent.com/TODOTODoTOdoTodotodo/petpet/main/install.sh | bash
```

- 최신 버전을 내려받아 `응용 프로그램` 폴더에 설치 후 바로 실행
- 관리자 암호 불필요. `/Applications`에 쓸 수 없으면 `~/Applications`에 설치
- 같은 줄을 다시 실행하면 최신 버전으로 업데이트
- 스크립트 내용: [`install.sh`](install.sh)

**DMG로 설치**

1. Releases에서 `DeskPet.dmg` 내려받기
2. DMG를 열고 `DeskPet.app`을 `응용 프로그램` 폴더로 끌기
3. 실행 후 메뉴바의 👾 아이콘 확인

**DMG로 설치했는데 처음 실행이 막히는 경우**

Apple 공증을 거치지 않은 앱이라, 브라우저로 받은 경우 처음 한 번 실행이 막힘. 터미널 한 줄 설치는 해당 없음.

1. `DeskPet.app` 한 번 실행 (차단 안내 표시)
2. 시스템 설정 ▸ 개인정보 보호 및 보안
3. 아래쪽 "DeskPet이(가) 차단되었습니다" 옆 **그래도 열기**
4. 다시 실행 후 **열기**

## 사용법

| 동작 | 결과 |
|---|---|
| 펫 클릭 | ❤️ 하고 깡충 (연달아 3번이면 💢 하고 도망) |
| 펫 끌기 | 집어 옮기기. 놓을 때 손을 휘두르면 던지기 |
| 펫 우클릭 | 캐릭터 바꾸기, 모자, 손에 들 물건, 이름, 펫 빼기 |
| 떨어진 물건 클릭 | 가까운 펫이 바로 주우러 감 |
| 메뉴바 👾 | 펫 추가·빼기, 기능 켜고 끄기, 도감, 언어 |

## 기능

### 움직임

- 창 위 걷기, 창 옆면 오르기, 창 끝에서 뛰어내리기
- 앞 창에 가려진 곳은 발판에서 제외
- 여러 모니터 지원. 옆 모니터로 걸어서 이동
- 창을 바꾸면 그 창으로 캐릭터별 스킬 도약(장대높이뛰기, 불꽃 로켓, 칼 도약 등)
- 최대화한 창에서는 윗변 뒤에 숨어 거꾸로 빼꼼
- 창 아랫면에 거꾸로 붙어 다니기
- 펫끼리 겹치지 않음. 길이 막히면 뛰어넘기, 결투, 돌아서기 중 하나
- 앱을 켜면 펫들이 한 마리씩 지금 보는 창 위로 내려와 👋

### 반응

- 입력이 3분 없으면 졸다가 잠듦(Zzz). 입력이 생기면 깜짝 깸
- 빠르게 타이핑하면 펫이 따라 두드림. 아주 빠르면 🔥
- 통화 중(마이크 사용 중)이면 조용히
- 창을 바꾸면 돌아보고, 앱 종류(메신저·메일·영상·개발 도구)에 맞게 한마디

### 놀이

- **펫 탑**: 펫이 다른 펫 머리 위로 올라탐. 최대 4층
- **기차놀이**: 한가한 펫들이 줄줄이 따라 걷기 🚂
- **티격태격**: 마주친 펫끼리 가벼운 대결 ✌️
- **포인터 장난**: 멈춘 포인터를 펫이 잠깐 들고 달아남. 마우스를 움직이면 바로 돌려줌. 기본 꺼짐

### 줍기와 도감

- 사용 중 6~18분마다 창 위나 바닥에 물건 하나
- 가장 가까운 펫이 주워 ✨. 드문 물건이면 🌟
- 물건 12종: 흔한 물건 6, 드문 물건 4, 계절 물건 2(12~2월 눈송이, 3~4월 벚꽃)
- 3분 안에 아무도 줍지 않으면 사라짐
- 메뉴 **도감**에서 모은 개수와 처음 찾은 날 확인

### 모자

- 모은 개수로 얻는 모자 8종 (예: 도토리 5개 → 도토리 모자, 별 조각 1개 → 별 모자)
- 얻는 순간 주운 펫이 🎩 하고 바로 씀
- 펫 우클릭 ▸ 모자로 바꾸기. 캐릭터를 바꿔도 유지
- 걷기·점프·잠 자세마다 머리 위치를 따라 모자도 움직임

### 친밀도

펫마다 ❤️가 쌓임. 줄어들지 않음.

| 쌓이는 일 | ❤️ | 하루 최대 |
|---|---|---|
| 30분 함께 있기 (사용 중) | +1 | 16 |
| 쓰다듬기 | +1 | 10 |
| 앱 켤 때 인사 | +1 | 1 |
| 물건 줍기 | +2 | 제한 없음 |
| 활약 (결투 승리, 기관차 도착, 탑 3층, 포인터 장난) | +1 | 5 |

| 레벨 | 필요한 ❤️ | 새로 생기는 것 |
|---|---|---|
| Lv.2 | 10 | 제자리 한 바퀴 ♪ |
| Lv.3 | 30 | 점프 중 공중제비 |
| Lv.4 | 60 | 모은 물건 하나를 손에 들기 |
| Lv.5 | 100 | 반짝 발자국 (❤️ 300 분홍, 500 금색) |
| Lv.6 | 150 | 이름 짓기 (쓰다듬으면 `❤️ 이름`) |

### 일정 말풍선

- 캘린더 일정 10분 전과 시작 시각, 미리 알림 마감 시각에 말풍선
- 펫을 클릭할 때까지 유지
- 일정이 여러 개면 다른 캐릭터의 전령 펫이 내려와 하나씩 맡음
- 메뉴에서 끄기, 일정 제목 숨기기(화면 공유용)

## 메뉴

| 메뉴 | 내용 | 기본값 |
|---|---|---|
| 따라갈 곳 | 보는 창 / 마우스 포인터 | 보는 창 |
| 스킬 도약 | 창을 바꾸면 그 창으로 도약 | 켬 |
| 모니터 따라가기 | 보는 모니터로 펫이 건너옴 | 켬 |
| 통화 중 조용히 | 마이크 사용 중이면 조용히 | 켬 |
| Claude 사용량만큼 지침 | 사용량이 많을수록 펫이 지침 (아래 참고) | 켬 |
| 타이핑 반응 | 빠르게 치면 따라 두드리기 | 켬 |
| 포인터 장난 | 펫이 포인터를 잠깐 들고 달아남 | 끔 |
| 던지기 정확도 | 늘 명중 / 자주 명중 / 가끔 명중 / 엉망 (캐릭터마다 조금씩 다름) | 자주 명중 |
| 휴식 알림 | 50분 연속 사용 시 기지개 🙆 | 끔 |
| 펫 크기 | 1.0x / 1.5x / 2.0x / 2.5x | 1.5x |
| 불투명도 | 100% / 75% / 50% | 100% |
| 일정 말풍선 | 캘린더·미리 알림 말풍선 | 켬 |
| 일정 제목 숨김 | 말풍선에 시각만 표시 | 끔 |
| 언어 · Language | 한국어 / English | 맥 언어 |

## 권한과 개인정보

| 항목 | 쓰는 것 | 권한 |
|---|---|---|
| 창 목록 | 창 위치·크기·앱 이름 (창 제목·내용은 읽지 않음) | 불필요 |
| 키보드 | 누른 횟수만 (어떤 키인지 모름) | 불필요 |
| 마이크 | 사용 중인지 여부만 (소리는 읽지 않음) | 불필요 |
| 포인터 | 위치. 포인터 장난을 켰을 때만 옮김 | 불필요 |
| 캘린더·미리 알림 | 일정 시각과 제목 (일정 말풍선을 켰을 때만) | 처음 한 번 요청 |

- 네트워크 연결 없음. 외부 서버로 보내는 데이터 없음
- 저장 위치
  - 설정·도감: 이 맥 안 (`com.deskpet.companion`)
  - 기록: `~/Library/Logs/DeskPet/pet_debug.log` (행동 변화만, 일정 제목·키 내용 없음)

## Claude 사용량 연동 (선택)

Claude Code 사용량이 많을수록 펫이 느려지고, 지치면 누워 쉼.
사용량이 초기화되면 ⚡ 하고 일어남.

- Claude Code 상태줄 스크립트가 남긴 파일만 읽음
- Claude 계정 정보·네트워크는 사용하지 않음
- Pro·Max 구독에서 Claude Code가 사용량 한도 값을 줄 때만 동작

Claude Code 상태줄 스크립트에 아래 줄 추가 (`jq` 필요).

```bash
pet_dir="$HOME/Library/Application Support/DeskPet"
mkdir -p "$pet_dir" && echo "$input" | jq -c '{five_hour: .rate_limits.five_hour, seven_day: .rate_limits.seven_day}' > "$pet_dir/claude-usage.json.tmp" && mv -f "$pet_dir/claude-usage.json.tmp" "$pet_dir/claude-usage.json"
```

`$input`은 상태줄 스크립트가 받은 JSON 전체. 상태줄 설정 방법은 [Claude Code 문서](https://code.claude.com/docs/en/statusline.md) 참고.

## 아이디어 보내기

[아이디어 제안 양식](https://github.com/TODOTODoTOdoTodotodo/petpet/issues/new?template=idea.yml)으로 이슈 등록.

- 펫이 했으면 하는 행동, 새 놀이, 새 캐릭터 등 무엇이든
- 검토 결과는 그 이슈에 댓글과 라벨로 남김: 수락 · 정보 더 필요 · 나중에 · 하지 않음
- 받지 않는 제안: 키 내용·창 내용·화면을 읽어야 하는 기능, 다른 게임 캐릭터를 그대로 옮기는 그림
- 오류 제보는 [일반 이슈](https://github.com/TODOTODoTOdoTodotodo/petpet/issues/new)로

## 문제 해결

| 증상 | 확인할 것 |
|---|---|
| 앱이 열리지 않음 | 위 "DMG로 설치했는데 처음 실행이 막히는 경우", 또는 터미널 한 줄 설치 |
| 펫이 안 보임 | 메뉴바 👾 확인. 없으면 앱 다시 실행 |
| 일정 말풍선이 안 뜸 | 시스템 설정 ▸ 개인정보 보호 및 보안 ▸ 캘린더·미리 알림에서 DeskPet 허용 |
| 포인터 장난이 안 됨 | 기록에 `pointer move failed`가 있으면 손쉬운 사용 권한 필요 |
| 동작 기록 확인 | 메뉴 ▸ 디버그 로그 열기 |

## 지우기

**터미널 한 줄**

```bash
curl -fsSL https://raw.githubusercontent.com/TODOTODoTOdoTodotodo/petpet/main/install.sh | bash -s -- --uninstall
```

**직접 지우기**

1. 메뉴 ▸ DeskPet 종료
2. `응용 프로그램`에서 `DeskPet.app` 삭제

**설정·도감까지 지우기** (두 방법 공통, 터미널에서 실행)

```bash
defaults delete com.deskpet.companion; rm -rf ~/Library/Logs/DeskPet ~/Library/Application\ Support/DeskPet
```

## 직접 빌드

필요: Xcode Command Line Tools (Swift 5.9 이상)

```bash
./scripts/verify.sh        # 검사 (가상 화면에서 행동 시나리오 실행)
./scripts/package_app.sh   # DeskPet.app, DeskPet.dmg, DeskPet.zip 생성 (공개용 캐릭터만)
open DeskPet.app
```

- 새 캐릭터 만들기: `Tools/SpriteForge` (도트 부위 그림 → 모든 동작 프레임)
- 구조와 동작 규칙: `HANDOVER.md`, `Controller/DESKTOP_PET_CONTROLLER.md`

## 라이선스와 출처

- 코드: MIT License (`LICENSE`)
- 캐릭터 그림

| 캐릭터 | 출처 | 라이선스 |
|---|---|---|
| NinjaFrog, MaskDude, PinkMan, VirtualGuy | "Pixel Adventure" by Pixel Frog — https://pixelfrog-assets.itch.io/pixel-adventure-1 | CC0 1.0 (출처 함께 표시) |
| Foxy, Opossum, Froggy | "Sunny Land" by Luis Zuno (ansimuz) — https://ansimuz.itch.io/sunny-land-pixel-game-art | CC0 1.0 |
| Elf, Wizard, Lizard, Dwarf, BigDemon | "16x16 DungeonTileset II" by 0x72 — https://0x72.itch.io/dungeontileset-ii | CC0 1.0 |
| NinjaGreen, Skeleton, Samurai, Princess, Knight | "Ninja Adventure" by Pixel-boy and AAA — https://pixel-boy.itch.io/ninja-adventure-asset-pack | CC0 1.0 |
| Nabi, Bolt | DeskPet 자체 제작 (SpriteForge) | MIT |

- 물건·모자·무기 도트: DeskPet 자체 제작 (MIT)
