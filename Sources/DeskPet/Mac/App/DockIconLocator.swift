import AppKit
import ApplicationServices

/// This object is responsible for finding where an app's icon sits in the Dock, through the Dock's accessibility
/// elements (the item whose file URL is the app, or failing that whose title is the app's name), in global Cocoa
/// coordinates. It needs the Accessibility permission, asks for it only when the user turns the feature on,
/// and reads nothing but the Dock items' names, places and sizes.
enum DockIconLocator {
    /// 손쉬운 사용 권한이 있는지
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 권한이 없으면 시스템 허용 창을 띄움 (허용은 사용자가 시스템 설정에서 직접)
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 그 앱의 Dock 아이콘 사각형. 권한이 없거나 Dock에 없으면 nil
    static func iconFrame(of app: NSRunningApplication) -> CGRect? {
        guard isTrusted, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let items = children(of: AXUIElementCreateApplication(dock.processIdentifier))
            .filter { string($0, kAXRoleAttribute) == kAXListRole as String }
            .flatMap(children(of:))
        let path = app.bundleURL?.standardizedFileURL.path
        let item = items.first { url(of: $0)?.standardizedFileURL.path == path && path != nil }
            ?? items.first { string($0, kAXTitleAttribute) == app.localizedName }
        guard let item, let origin = point(item), let size = size(item), size.width > 0,
              let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else { return nil }
        // 손쉬운 사용 좌표는 주 모니터 왼쪽 위 기준, 아래로 +
        return CGRect(x: origin.x, y: primary.frame.maxY - origin.y - size.height, width: size.width, height: size.height)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func url(of element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success else { return nil }
        return value as? URL
    }

    private static func point(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }
}
