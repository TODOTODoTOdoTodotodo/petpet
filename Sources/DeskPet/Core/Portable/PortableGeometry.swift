import Foundation

#if canImport(CoreGraphics)
// 맥: CGRect의 midX 같은 멤버는 CoreGraphics에 있음. 한 곳에서 모듈 전체에 들여옴
@_exported import CoreGraphics
#else
/// This object is responsible for the 2D vector type the pet code uses for velocities and pushes,
/// on systems whose Foundation has CGPoint·CGSize·CGRect but no CGVector (Windows, Linux).
struct CGVector: Equatable {
    var dx: CGFloat
    var dy: CGFloat

    init(dx: CGFloat, dy: CGFloat) {
        self.dx = dx
        self.dy = dy
    }

    init(dx: Double, dy: Double) {
        self.init(dx: CGFloat(dx), dy: CGFloat(dy))
    }

    init(dx: Int, dy: Int) {
        self.init(dx: CGFloat(dx), dy: CGFloat(dy))
    }

    static let zero = CGVector(dx: CGFloat(0), dy: CGFloat(0))
}
#endif
