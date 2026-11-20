import Foundation

/// 사용자가 다른 창으로 옮겨 간 순간
struct FocusShift: Equatable {
    /// 직전에 보던 창
    let from: UInt32?
    let to: UInt32
    /// 새 창의 위치
    let frame: CGRect
    let category: AppCategory
}

/// This object is responsible for noticing, once per change, that the user moved to another window
/// (or that the window the pets chase changed).
final class FocusTracker {
    private var last: UInt32?

    /// 사용자가 보고 있는 창 기준
    func update(from world: World) -> FocusShift? {
        update(to: world.focusedWindowID, in: world)
    }

    /// 주어진 창 기준 (쫓을 창)
    func update(to current: UInt32?, in world: World) -> FocusShift? {
        guard current != last else { return nil }
        defer { last = current }
        guard let current, let window = world.window(id: current) else { return nil }
        return FocusShift(from: last, to: current, frame: window.frame, category: AppCategory(bundleID: world.focusedBundleID))
    }
}

/// This object is responsible for sorting apps into the few kinds pets react to differently,
/// by bundle ID rules only (no window titles or contents).
enum AppCategory: Equatable, Hashable {
    case chat
    case mail
    case video
    case code
    case other

    /// 번들 ID 규칙표 (정확히 같거나, 점으로 끝나는 항목은 접두사)
    private static let rules: [(prefix: String, category: AppCategory)] = [
        ("com.tinyspeck.slackmacgap", .chat), ("com.kakao.KakaoTalkMac", .chat), ("com.apple.MobileSMS", .chat),
        ("com.microsoft.teams", .chat), ("com.microsoft.teams2", .chat), ("com.hnc.Discord", .chat), ("jp.naver.line.mac", .chat),
        ("ru.keepcoder.Telegram", .chat), ("net.whatsapp.WhatsApp", .chat),
        ("com.apple.mail", .mail), ("com.microsoft.Outlook", .mail),
        ("com.apple.TV", .video), ("com.colliderli.iina", .video), ("org.videolan.vlc", .video),
        ("com.apple.QuickTimePlayerX", .video),
        ("com.apple.dt.Xcode", .code), ("com.microsoft.VSCode", .code), ("com.jetbrains.", .code),
        ("com.googlecode.iterm2", .code), ("com.apple.Terminal", .code), ("dev.warp.", .code),
        ("com.todesktop.230313mzl4w4u92", .code), ("com.sublimetext.", .code),
    ]

    init(bundleID: String?) {
        guard let bundleID else {
            self = .other
            return
        }
        self = Self.rules.first { rule in
            rule.prefix.hasSuffix(".") ? bundleID.hasPrefix(rule.prefix) : bundleID == rule.prefix
        }?.category ?? .other
    }

    /// 그 앱으로 옮겼을 때 펫이 하는 말
    var remark: String? {
        switch self {
        case .chat: return "💬"
        case .mail: return "📨"
        case .video: return "🍿"
        case .code: return "⌨️"
        case .other: return nil
        }
    }
}
