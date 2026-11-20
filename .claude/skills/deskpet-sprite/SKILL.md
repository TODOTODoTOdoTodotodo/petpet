---
name: deskpet-sprite
description: Create a new DeskPet character or add animations to one, without extra subscriptions or API calls. The agent draws layered 48x48 pixel-art parts as text grids, and SpriteForge builds every animation (idle, walk, jump, hang, sleep, attack) deterministically. Optionally turns a picture the user made in their own Gemini app into a pixel draft. Use when the user asks for a new pet character, a new skin, or better character animations in this repository.
---

# DeskPet 캐릭터 제작 (sprite-gen 기조, 추가 비용 없음)

aldegad/sprite-gen의 "그림 한 장 → 게임용 스프라이트" 흐름을 이 저장소 안에서 쓰도록 옮긴 스킬이다.
**생성은 그림 단계에만, 동작 프레임·변환·검증은 코드로.**

| 단계 | 누가 | 비용 |
|---|---|---|
| 디자인·부위 도트 그리기 | 지금 이 에이전트 (텍스트 격자) | 추가 없음 |
| 참고 그림 (선택) | 사용자의 개인 Gemini 앱 → `pixelize` | 구독 범위, API 없음 |
| 동작 프레임 생성 | `SpriteForge build` (결정론적) | 0 |
| 스킨 변환·검증 | `SpriteForge`, `./scripts/verify.sh` | 0 |
| 앱 실행 | PNG만 읽음 | 0 |

외부 API 키, 유료 호출, 다른 구독을 쓰지 않는다. 사내 계정도 쓰지 않는다.

## 1. 요청 정리
- 이름(영문, 폴더명), 생김새 한두 줄, 스킬(`pole_vault` · `flame_rocket` · `slash_jump` · `big_jump`), 색 느낌을 정한다.
- **독자 디자인만.** 기존 게임·애니메이션·브랜드 캐릭터를 따라 그리거나 이름을 빌리지 않는다. 요청이 그런 쪽이면 일반적인 동물·사물·직업 캐릭터로 바꿔 제안한다.
- 기존 스킨(`Assets/Skins/*`)을 덮어쓰지 않는다. 새 이름을 쓴다.

## 2. (선택) Gemini 참고 그림
디자인을 말로 정하기 어려울 때만 쓴다. 사용자에게 아래 문구를 그대로 Gemini 앱에 붙여 넣고 이미지를 저장해 경로를 알려 달라고 한다.

```
Pixel art game sprite of <생김새>, full body, side view facing LEFT, chibi proportions
(head about 40% of height), standing pose with arms down and legs slightly apart,
clean 1-pixel dark outline, limited palette of about 8 colors, flat colors, no shading gradients,
single character centered on a plain solid white background, no text, no shadow on the ground.
```

받은 이미지로 초안을 만든다.

```bash
swift run SpriteForge pixelize <이미지 경로> --out Assets/Rigs/<이름>.rig.json --height 30 --colors 10
```

`--flip`: 캐릭터가 오른쪽을 보면 붙인다. 초안은 `body` 한 장이라, 아래 3단계처럼 부위로 나눠야 동작이 산다.

## 3. 리그 그리기 (`Assets/Rigs/<이름>.rig.json`)
```json
{
  "name": "Nabi",
  "skill": "big_jump",
  "facing": "west",
  "canvas": 48,
  "palette": { "k": "#2b1d1a", "o": "#f0a04b" },
  "layers": {
    "tail":     { "at": [x, y], "rows": ["..k", ".ko"] },
    "backLeg":  { "at": [x, y], "rows": ["..."] },
    "backArm":  { "at": [x, y], "rows": ["..."] },
    "body":     { "at": [x, y], "rows": ["..."] },
    "frontLeg": { "at": [x, y], "rows": ["..."] },
    "head":     { "at": [x, y], "rows": ["..."] },
    "frontArm": { "at": [x, y], "rows": ["..."] }
  },
  "overlays": {
    "eyesClosed": { "at": [x, y], "rows": ["kk"] },
    "prop":       { "at": [x, y], "rows": ["..."] }
  }
}
```

규칙:
- 칸 48x48, `at`은 부위 왼쪽 위 칸 (y는 위에서 아래). `.`은 투명, 나머지 글자는 `palette` 키(한 글자).
- **왼쪽(west)을 보는 옆모습**으로 그린다. 오른쪽은 앱이 좌우 반전한다.
- 발바닥(가장 아랫줄)은 44번 줄 근처. 키 24~32px, 폭 22px 이내. 기존 캐릭터(몸 16~20 x 26~30px)와 비슷하게.
- 색 12개 이하, 바깥 1px 어두운 외곽선.
- 그리는 순서(뒤→앞): `tail, backLeg, backArm, body, frontLeg, head, frontArm`. 겹치는 부분은 앞 부위가 덮는다.
- **팔·다리의 윗줄 가운데가 어깨·엉덩이 축**이다. 팔은 아래로 늘어뜨린 모양으로 그린다(위로 뒤집기·앞으로 90도 회전이 이 축 기준).
- `body`만 필수. 다리가 없으면 걷기는 몸만 들썩이고, 팔이 없으면 매달리기·공격이 밋밋해진다.
- `eyesClosed`는 눈 자리를 덮는 작은 조각(깜빡임·잠). `prop`은 앞팔에 붙어 함께 돌아가는 소품.
- 큰 격자는 한 번에 쓰기 어렵다. 머리 → 몸 → 다리 → 팔 순서로 부위마다 행 길이를 세며 쓴다.

## 4. 만들기와 확인
```bash
swift run SpriteForge check Assets/Rigs/<이름>.rig.json
swift run SpriteForge build Assets/Rigs/<이름>.rig.json --preview <scratchpad>/<이름>.png
```
- `build`는 `Assets/Skins/<이름>/`에 PNG와 `metadata.json`을 만든다. 경고(칸 밖 픽셀, 빈 프레임)가 있으면 저장하지 않는다.
- **미리보기 PNG를 Read로 직접 보고** 아래를 확인한다. 고칠 점이 있으면 리그를 고쳐 다시 만든다(최대 3번 반복 후 사용자에게 보여 줌).
  - 대기: 왼쪽을 보는가, 외곽선이 끊기지 않았는가
  - 걷기: 다리가 번갈아 움직이는가, 반전 줄은 오른쪽을 보는가
  - 매달리기: 손이 머리 위로, 몸이 떨어져 보이지 않는가
  - 공격: 앞팔이 앞으로 뻗는가
- 생성된 스킨 폴더는 손으로 고치지 않는다. 항상 리그를 고쳐 다시 만든다.

## 5. 앱에 넣기
```bash
./scripts/verify.sh
./scripts/package_app.sh
```
- `verify.sh`는 모든 리그를 다시 만들어 `Assets/Skins`와 같은지도 확인한다.
- 실행 후 펫을 우클릭하거나 메뉴 👾 → Pets / Add Pet / All Pets As에서 고른다. 사용자에게 미리보기 경로와 결과를 보여 준다.

## 무료 에셋 시트 가져오기
남이 그린 스프라이트 시트(프레임을 가로로 이은 PNG)를 쓸 때.
1. 라이선스부터 확인한다. CC0·CC-BY만 쓴다(재배포 금지·변경 금지(ND)는 앱에 넣을 수 없음). 내려받기는 사용자에게 파일 이름·출처·크기를 말하고 허락받는다.
2. 필요한 줄 PNG만 `Assets/Sources/<팩>/<캐릭터>/`에 두고 `SOURCE.md`·`LICENSE.txt`에 출처와 라이선스를 적는다.
3. `Assets/Rigs/<이름>.import.json`을 쓴다(예: `NinjaFrog.import.json`). 동작 이름은 앱 칸(`Idle`, `Walking`, `Jump`, `Hang`, `Sleep`, `Climb`, `swing_attack`)에 맞춘다. 원본이 오른쪽을 보면 `"facing": "east"`.
4. `swift run SpriteForge import Assets/Rigs/<이름>.import.json --preview <scratchpad>/<이름>.png`로 만들고 미리보기를 본다(발·머리 잘림, 반전 방향, 매달리기 높이).
   - 열 = 방향, 줄 = 프레임인 시트(위에서 내려다본 RPG 시트)는 동작마다 `"column"`으로 옆모습 열을 고른다. 작은 그림은 `"scale": 2`, 칸에 여백이 많으면 `"crop": [x, y, 폭, 높이]`.
   - 후보가 많으면 먼저 scratchpad에 설정을 만들어 미리보기만 보고, 고른 캐릭터만 `Assets/Sources`·`Assets/Rigs`에 넣는다.

## 원본 스킨에 매달리기 더하기
부위가 나뉘지 않은 기존 스킨(통짜 PNG)은 `SpriteForge hang`으로 매달리기 4프레임을 만든다.
1. 픽셀 덤프로 바탕 이미지(뒷모습 `north`가 있으면 그것, 없으면 정면 `south`)에서 팔 사각형을 찾는다. 윗줄이 어깨, 아랫줄이 손 끝.
2. `Assets/Rigs/<스킨>.hang.json`에 적는다.
   ```json
   { "skin": "Goblin", "base": "<폴더>/rotations/north.png", "direction": "north",
     "arms": [{ "at": [16, 26], "size": [4, 5] }, { "at": [28, 26], "size": [4, 5] }],
     "legsFrom": 34 }
   ```
   선택: 팔별 `"shift"`(든 팔 가로 이동), `"reach"`(손이 머리 위로 올라가는 줄 수, 기본 2).
3. `swift run SpriteForge hang Assets/Rigs/<스킨>.hang.json --preview <scratchpad>/<스킨>_hang.png`로 만들고 미리보기를 본다.
   - 손이 귀·뿔처럼 보이면 `reach`를 3~4로 올려 소매가 보이게 한다.
   - 팔을 뗀 자리에 몸 조각이 남으면 사각형을 넓힌다.

## 앱이 쓰는 동작 칸
`Walking`(8) · `Idle`(6) · `Jump`(1) · `Hang`(4) · `Sleep`(2) · `swing_attack`(4)을 SpriteForge가 모두 만든다.
자세한 대체 규칙은 `Controller/DESKTOP_PET_CONTROLLER.md` 7·8절.
