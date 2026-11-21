import Foundation

/// 한 무대에 그릴 펫 하나의 모습 (전역 좌표)
struct PetDrawing<Frame> {
    let id: String
    let frame: SpriteFrame<Frame>
    /// 스프라이트 칸의 전역 좌표 사각형
    let rect: CGRect
    /// 있으면 숨쉬듯 세로로 들썩이는 위상
    let breathPhase: Double?
    let speech: Speech?
    /// 스킬 도약 꼬리 입자 스타일
    let trail: SkillStyle?
    /// 발 위치와 몸 높이 (입자 위치용)
    let foot: CGPoint
    let bodyHeight: CGFloat
    /// 말풍선 꼬리가 가리킬 머리 위 지점
    let speechAnchor: CGPoint
    /// 불투명도 (모니터 건너가기)
    var alpha: CGFloat = 1
    /// rect 안에서 위아래를 뒤집어 그림 (거꾸로 빼꼼)
    var upsideDown = false
    /// 이 높이(전역 y)보다 위는 그리지 않음
    var hiddenAbove: CGFloat?
    /// 쓰고 있는 모자와 자리
    var hat: (kind: HatKind, frame: HatFrame)?
    /// 앞손에 든 물건과 자리 (Lv.4)
    var held: (kind: ItemKind, rect: CGRect)?
    /// 몸을 돌려 그리는 각도 (공중제비)
    var rotation: CGFloat = 0
    /// 걸을 때 반짝 발자국 (Lv.5)
    var sparkles = false
    /// 발자국 색 단계 (0 기본, 1 분홍, 2 금색)
    var sparkleTier = 0

    /// rect 중 그려지는 아래쪽 비율 (0이면 다 가려짐)
    var shownShare: CGFloat {
        guard let hiddenAbove else { return 1 }
        return min(max((hiddenAbove - rect.minY) / rect.height, 0), 1)
    }
}

/// 한 무대에 그릴 무기 하나 (전역 좌표)
struct ProjectileDrawing {
    let id: String
    let kind: ProjectileKind
    let center: CGPoint
    let rotation: CGFloat
    /// 도트 한 칸 크기
    let scale: CGFloat
    /// 닿은 뒤 반짝임 진행 (0~1). 날아가는 중이면 nil
    let burst: Double?
    /// 포인터를 빗나갔는지 (반짝임 대신 먼지)
    let missed: Bool

    init(_ projectile: Projectile) {
        missed = projectile.missed
        id = projectile.id
        kind = projectile.kind
        center = projectile.position
        rotation = projectile.rotation
        scale = projectile.scale
        burst = projectile.burstProgress
    }
}

/// 한 무대에 그릴 물건 하나 (전역 좌표)
struct ItemDrawing {
    let id: String
    let kind: ItemKind
    /// 그림 사각형
    let rect: CGRect
    let alpha: CGFloat
    /// 드문 물건의 반짝임, 또는 클릭했을 때의 반짝임 세기 (0이면 없음)
    let sparkle: CGFloat
    /// 드문 물건이 메뉴바로 날아가며 반짝임 꼬리를 남기는지
    let trail: Bool

    init(_ item: DroppedItem, clock: TimeInterval) {
        id = item.id
        kind = item.kind
        rect = item.rect
        alpha = item.isBlinkedOut ? 0.15 : CGFloat(1 - 0.4 * (item.flightProgress ?? 0))
        let flash = CGFloat(item.flashLeft / DroppedItem.flashTime)
        let rare = item.kind.rarity == .rare && item.flightProgress == nil ? CGFloat(0.35 + 0.35 * sin(clock * 5)) : 0
        sparkle = max(flash, rare)
        trail = item.kind.rarity == .rare && item.isFlying
    }
}
