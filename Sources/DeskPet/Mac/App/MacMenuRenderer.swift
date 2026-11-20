import AppKit

/// This object is responsible for turning the shared menu data (`MenuNode`) into `NSMenu`s —
/// titles, check marks, dot-art icons, tooltips and key equivalents — and handing the chosen
/// `MenuCommand` (or a submenu's open notice) back to the shared code.
final class MacMenuRenderer: NSObject, NSMenuDelegate {
    private let onCommand: (MenuCommand) -> Void

    init(onCommand: @escaping (MenuCommand) -> Void) {
        self.onCommand = onCommand
    }

    func menu(from nodes: [MenuNode]) -> NSMenu {
        commandMenu(from: nodes)
    }

    private func commandMenu(from nodes: [MenuNode]) -> CommandMenu {
        let menu = CommandMenu()
        nodes.map(item(from:)).forEach(menu.addItem)
        return menu
    }

    private func item(from node: MenuNode) -> NSMenuItem {
        switch node.kind {
        case .separator:
            return .separator()
        case .heading:
            let heading = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            heading.isEnabled = false
            return heading
        case .info:
            // 보기만 하는 줄: 흐리게 보이지 않게 아무 일 없는 동작을 둠
            return decorated(NSMenuItem(title: node.title, action: #selector(noop), keyEquivalent: ""), node)
        case .command(let command):
            let row = decorated(NSMenuItem(title: node.title, action: #selector(choose(_:)), keyEquivalent: node.key), node)
            row.representedObject = CommandBox(command)
            return row
        case .submenu(let children, let onOpen):
            let parent = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
            let submenu = commandMenu(from: children)
            submenu.onOpen = onOpen
            submenu.delegate = onOpen == nil ? nil : self
            parent.submenu = submenu
            return parent
        }
    }

    private func decorated(_ row: NSMenuItem, _ node: MenuNode) -> NSMenuItem {
        row.target = self
        row.state = node.checked ? .on : .off
        row.isEnabled = node.enabled
        row.toolTip = node.toolTip
        if let icon = node.icon {
            row.image = DotArt.icon(named: icon.name, rows: icon.rows, palette: icon.palette, silhouette: icon.silhouette)
        }
        return row
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        onCommand(box.command)
    }

    @objc private func noop() {}

    func menuWillOpen(_ menu: NSMenu) {
        guard let onOpen = (menu as? CommandMenu)?.onOpen else { return }
        onCommand(onOpen)
    }
}

/// This object is responsible for an `NSMenu` that remembers which command to report when it opens.
private final class CommandMenu: NSMenu {
    var onOpen: MenuCommand?
}

/// This object is responsible for carrying a Swift `MenuCommand` in an `NSMenuItem`'s represented object.
private final class CommandBox {
    let command: MenuCommand

    init(_ command: MenuCommand) {
        self.command = command
    }
}

/// This object is responsible for the confirm and text-entry dialogs a menu choice needs on macOS (`NSAlert`).
final class MacMenuDialogs: MenuDialogs {
    func confirm(title: String, message: String, confirm: String, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    func askText(title: String, message: String, initial: String, save: String, cancel: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: save)
        alert.addButton(withTitle: cancel)
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = field
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
