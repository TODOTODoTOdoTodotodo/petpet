import CoreGraphics
import SpriteKit

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
