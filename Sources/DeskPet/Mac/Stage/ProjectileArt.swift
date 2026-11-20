import CoreGraphics
import SpriteKit

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

    init(_ projectile: Projectile) {
        id = projectile.id
        kind = projectile.kind
        center = projectile.position
        rotation = projectile.rotation
        scale = projectile.scale
        burst = projectile.burstProgress
    }
}

/// This object is responsible for the weapons' and burst textures, drawn from their text pixel grids once per kind.
enum ProjectileArt {
    static func texture(for kind: ProjectileKind) -> SKTexture {
        DotArt.texture(named: kind.name, rows: kind.rows, palette: kind.palette)
    }

    static var burst: SKTexture {
        DotArt.texture(named: "burst", rows: ProjectileKind.burstRows, palette: ProjectileKind.burstPalette)
    }

    static func texture(for hat: HatKind) -> SKTexture {
        DotArt.texture(named: "hat." + hat.id, rows: hat.rows, palette: hat.palette)
    }

    static func texture(for item: ItemKind) -> SKTexture {
        DotArt.texture(named: "item." + item.id, rows: item.rows, palette: item.palette)
    }
}
