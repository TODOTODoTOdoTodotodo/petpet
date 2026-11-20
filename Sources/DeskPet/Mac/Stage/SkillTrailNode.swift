import AppKit
import SpriteKit

/// This object is responsible for the particle trail behind a pet's skill leap (dust, flame or slash wind),
/// built in code so no particle files are needed. Particles live in the scene so they stay where they were emitted.
final class SkillTrailNode: SKEmitterNode {
    private var style: SkillStyle?

    /// 작은 원 모양 입자 텍스처 (한 번 만들어 공유)
    private static let dot: SKTexture = {
        let size = 8
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        return SKTexture(image: image)
    }()

    override init() {
        super.init()
        particleTexture = Self.dot
        particleBirthRate = 0
        particleColorBlendFactor = 1
        emissionAngleRange = .pi * 2
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 스타일이 바뀔 때만 입자 설정을 다시 함. nil이면 새 입자를 멈춤 (남은 입자는 자연히 사라짐)
    func emit(_ next: SkillStyle?) {
        guard let next else {
            particleBirthRate = 0
            return
        }
        if next != style {
            style = next
            configure(for: next)
        }
    }

    /// 입자가 나올 위치 (발 또는 몸 중심)
    func anchorOffset(bodyHeight: CGFloat) -> CGFloat {
        style == .slashJump ? bodyHeight * 0.55 : 2
    }

    private func configure(for style: SkillStyle) {
        switch style {
        case .flameRocket:
            particleColorSequence = SKKeyframeSequence(
                keyframeValues: [NSColor(red: 1, green: 0.95, blue: 0.5, alpha: 1), NSColor(red: 1, green: 0.45, blue: 0.1, alpha: 1),
                                 NSColor(red: 0.6, green: 0.1, blue: 0.05, alpha: 1)],
                times: [0, 0.4, 1])
            particleBirthRate = 140
            particleLifetime = 0.45
            particleSpeed = 70
            particleSpeedRange = 30
            emissionAngle = -.pi / 2
            emissionAngleRange = 0.7
            particleScale = 0.9
            particleScaleSpeed = -1.6
            particleAlphaSpeed = -1.8
        case .slashJump:
            particleColorSequence = nil
            particleColor = NSColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)
            particleBirthRate = 110
            particleLifetime = 0.35
            particleSpeed = 90
            particleSpeedRange = 40
            emissionAngleRange = .pi * 2
            particleScale = 0.7
            particleScaleSpeed = -1.5
            particleAlphaSpeed = -2.6
        case .poleVault, .bigJump:
            particleColorSequence = nil
            particleColor = NSColor(red: 0.72, green: 0.62, blue: 0.5, alpha: 1)
            particleBirthRate = 220
            particleLifetime = 0.6
            particleSpeed = 55
            particleSpeedRange = 35
            emissionAngle = .pi / 2
            emissionAngleRange = .pi
            particleScale = 1.0
            particleScaleSpeed = -1.2
            particleAlphaSpeed = -1.5
        }
    }
}
