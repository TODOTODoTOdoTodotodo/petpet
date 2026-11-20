import AppKit

/// This object is responsible for a contact sheet of every generated frame (4x, checkerboard background),
/// including the mirrored walk, so an agent or person can review the character at a glance.
enum Preview {
    static let scale = 4

    static func write(name: String, animations: [RenderedAnimation], to url: URL) throws {
        var rows: [(String, [PixelGrid])] = animations.map { ($0.key, $0.frames) }
        if let walk = animations.first(where: { $0.key == "Walking" }) {
            rows.append(("Walking (반전)", walk.frames.map(Raster.mirrored)))
        }
        guard let canvas = rows.first?.1.first?.count else { return }
        let cell = canvas * scale
        let labelWidth = 150
        let columns = rows.map(\.1.count).max() ?? 1
        let width = labelWidth + columns * (cell + 8)
        let height = rows.count * (cell + 8) + 30

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 14)]
        (name as NSString).draw(at: NSPoint(x: 8, y: height - 22), withAttributes: bold)

        for (rowIndex, row) in rows.enumerated() {
            let y = height - 30 - (rowIndex + 1) * (cell + 8)
            (row.0 as NSString).draw(at: NSPoint(x: 8, y: y + cell / 2), withAttributes: bold)
            for (column, frame) in row.1.enumerated() {
                let rect = NSRect(x: labelWidth + column * (cell + 8), y: y, width: cell, height: cell)
                drawChecker(in: rect)
                if let cg = Raster.cgImage(frame) {
                    NSImage(cgImage: cg, size: NSSize(width: canvas, height: canvas)).draw(in: rect)
                }
            }
        }
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ForgeError(description: "미리보기 저장 실패")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    /// 투명 영역이 보이도록 체크무늬 (도트 4칸 = 1칸)
    private static func drawChecker(in rect: NSRect) {
        let square = CGFloat(scale * 4)
        var y = rect.minY
        var rowIndex = 0
        while y < rect.maxY {
            var x = rect.minX
            var columnIndex = 0
            while x < rect.maxX {
                ((rowIndex + columnIndex) % 2 == 0 ? NSColor(white: 0.82, alpha: 1) : NSColor(white: 0.72, alpha: 1)).setFill()
                NSRect(x: x, y: y, width: min(square, rect.maxX - x), height: min(square, rect.maxY - y)).fill()
                x += square
                columnIndex += 1
            }
            y += square
            rowIndex += 1
        }
    }
}
