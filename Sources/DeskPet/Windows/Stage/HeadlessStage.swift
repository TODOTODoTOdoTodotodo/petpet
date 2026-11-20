import Foundation

/// This object is responsible for standing in for the overlay stages until they draw (phase 2c):
/// it composes every tick's scene with the shared composer and remembers its size for the smoke report,
/// but puts nothing on screen and never takes the mouse.
final class HeadlessStage: PetStage {
    private let composer = SceneComposer<WinSprite>.forSkins()
    private(set) var areas: [ScreenArea] = []
    private(set) var lastDrawings = 0

    func rebuild(for areas: [ScreenArea]) {
        self.areas = areas
    }

    func render(_ pets: [Pet], projectiles: [Projectile], items: [DroppedItem], discreet: Bool) {
        lastDrawings = composer.compose(pets, projectiles: projectiles, items: items, discreet: discreet).pets.count
    }

    func routeMouse(at cursor: CGPoint, toPets wantsMouse: Bool) {}
}
