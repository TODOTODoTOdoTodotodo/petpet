# Desktop Pet Controller Domain Analysis & Design

## 1. Overview
본 도메인은 맥OS 상주형 데스크톱 펫(Desktop Pet / Screenmate) 시스템의 메인 제어 계층(Controller Layer)을 정의한다.
사용자의 화면 작업(클릭, 드래그, 타이핑)에 영향을 주지 않는 백그라운드 이벤트 관통을 기본으로 유지하면서, 듀얼 모니터(맥북 내장 + 외장 모니터) 및 가상 데스크톱(Spaces)을 자유롭게 넘나들고, **실제 화면의 창(Window) 및 소형 UI 객체 테두리를 발판과 벽으로 정확히 인식하여 오르고, 뛰어내리고, 걷는 물리 인터랙션**을 총괄 제어한다.

---

## 2. Core Controllers & Responsibilities

### 2.1 Single Pet Policy (단일 캐릭터 원칙)
- 다중 모니터 환경에서도 기본적으로 1개의 펫만 노출되도록 제어(`PetController`). 사용자가 원할 때만 명시적으로 추가하도록 제한.

### 2.2 Absolute Size Architecture (크기 변동 0% 보장 원칙)
- `xScale/yScale`은 **오직 좌우 반전(-1.0 / +1.0)에만 사용**.
- 실제 렌더링 크기는 `spriteNode.size = CGSize(width: 48 * visualScale, height: 48 * visualScale)`로 **절대 크기 단일화**.

### 2.3 Precise Geometric Collider System (`PetNode.swift`)
- **창 및 내부 오브젝트 인식 (Geometric Collision Rules):**
  1. **창 상단 타이틀바 (Roof Platform):** `win.maxY` 라인 주변부 착지.
  2. **창 좌/우 수직 외벽 (Vertical Walls):** 오직 실제 감지된 창의 외곽선에 부딪혔을 때만 등반. 화면 가장자리(Screen Edge) 등 가상의 벽은 기어오르지 않도록 방어.
  3. **보이지 않는 가상의 창문(투명 레이어) 등반 방지:** `WindowObserver`에서 최소 인식 크기를 다시 100x100으로 롤백하여, 운영체제가 생성하는 각종 투명 시스템 레이어(크기가 작은 더미 창)를 기어오르는 현상을 차단.

### 2.4 Multi-Display Global Drag & Drop (`OverlayController.swift`)
- 맥북 Retina + 외장 모니터 간 자연스러운 이동을 위해, 드래그 앤 드롭 이벤트를 개별 Scene이 아닌 `OverlayController`가 전역으로 관리(`addLocalMonitorForEvents`).
- 마우스 드래그 상태를 유지한 채 모니터 경계를 넘을 경우, 즉시 대상 모니터의 Scene으로 펫을 트랜싯하고 드래그 상태를 연속 유지함.

### 2.5 Enhanced Behavior (행동 패턴 다변화)
- 기존의 단순한 (걷기, 대기) 패턴을 넘어, 짧은 대쉬(Sprint), 연속 점프, 배회 등 상태 천이(FSM) 확률과 액션을 다변화하여 생동감 부여.

---

## 3. Documentation First Policy Verification
본 문서는 단일 펫 정책, 전역 드래그 앤 드롭, 화면 가장자리 벽 등반 금지, 소형 객체(20px) 감지, 행동 패턴 고도화를 위한 도메인 명세를 선행 갱신하였다.
