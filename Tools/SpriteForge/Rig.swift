import Foundation

/// RGBA 색 (0~255, 미리 곱하지 않은 값)
struct RGBA: Hashable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

/// 도구 오류 (사람이 읽을 메시지)
struct ForgeError: Error, CustomStringConvertible {
    let description: String
}

/// This object is responsible for one pixel-art part of a character: its pixels and where it sits on the canvas at rest.
struct Layer {
    /// 왼쪽 위 칸 위치 (y는 위에서 아래)
    let x: Int
    let y: Int
    /// 위에서 아래 줄, 투명은 nil
    let pixels: [[RGBA?]]

    var width: Int { pixels.first?.count ?? 0 }
    var height: Int { pixels.count }
    /// 팔·다리를 돌릴 때의 축 (윗변 가운데 = 어깨·엉덩이)
    var pivot: (x: Int, y: Int) { (x + width / 2, y) }
}

/// This object is responsible for reading and validating a character rig (`*.rig.json`):
/// palette, named body parts drawn as text grids, facing, and the skill name.
struct Rig {
    /// 뒤에서 앞으로 그리는 순서
    static let drawOrder = ["tail", "backLeg", "backArm", "body", "frontLeg", "head", "frontArm"]
    /// 상황에 따라 겹쳐 그리는 부위
    static let overlayNames = ["eyesClosed", "prop"]
    static let requiredLayers = ["body"]
    static let maxColors = 12

    let name: String
    let skill: String
    let facingWest: Bool
    let canvas: Int
    let layers: [String: Layer]
    let overlays: [String: Layer]
    let colorCount: Int
    /// 던지기 성격 (맞힐 확률에 더하는 값, 선택)
    var aim: Double?

    var directionName: String { facingWest ? "west" : "east" }

    static func load(_ url: URL) throws -> Rig {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ForgeError(description: "\(url.lastPathComponent): JSON 객체가 아님")
        }
        var problems: [String] = []

        let name = json["name"] as? String ?? url.deletingPathExtension().deletingPathExtension().lastPathComponent
        let skill = json["skill"] as? String ?? "big_jump"
        let facing = json["facing"] as? String ?? "west"
        if facing != "west" && facing != "east" { problems.append("facing은 west 또는 east") }
        let canvas = json["canvas"] as? Int ?? 48

        let palette = parsePalette(json["palette"], problems: &problems)
        let layerTable = json["layers"] as? [String: Any] ?? [:]
        let overlayTable = json["overlays"] as? [String: Any] ?? [:]

        for unknown in layerTable.keys where !drawOrder.contains(unknown) {
            problems.append("알 수 없는 부위 '\(unknown)' (가능: \(drawOrder.joined(separator: ", ")))")
        }
        for unknown in overlayTable.keys where !overlayNames.contains(unknown) {
            problems.append("알 수 없는 겹침 '\(unknown)' (가능: \(overlayNames.joined(separator: ", ")))")
        }
        for required in requiredLayers where layerTable[required] == nil {
            problems.append("필수 부위 '\(required)' 없음")
        }

        let layers = parseLayers(layerTable, palette: palette, canvas: canvas, problems: &problems)
        let overlays = parseLayers(overlayTable, palette: palette, canvas: canvas, problems: &problems)
        if palette.count > maxColors {
            problems.append("색 \(palette.count)개 (최대 \(maxColors))")
        }

        guard problems.isEmpty else {
            throw ForgeError(description: "\(url.lastPathComponent) 문제:\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
        }
        return Rig(name: name, skill: skill, facingWest: facing == "west", canvas: canvas,
                   layers: layers, overlays: overlays, colorCount: palette.count, aim: (json["aim"] as? NSNumber)?.doubleValue)
    }

    private static func parsePalette(_ value: Any?, problems: inout [String]) -> [Character: RGBA] {
        guard let table = value as? [String: String] else {
            problems.append("palette 없음 (예: {\"k\": \"#2b1d1a\"})")
            return [:]
        }
        var palette: [Character: RGBA] = [:]
        for (key, hex) in table {
            guard key.count == 1, let symbol = key.first, symbol != "." else {
                problems.append("palette 키 '\(key)'는 '.'이 아닌 한 글자여야 함")
                continue
            }
            guard let color = parseHex(hex) else {
                problems.append("palette '\(key)': 색 '\(hex)' 해석 불가 (#rrggbb 또는 #rrggbbaa)")
                continue
            }
            palette[symbol] = color
        }
        return palette
    }

    static func parseHex(_ text: String) -> RGBA? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            return RGBA(r: UInt8((value >> 16) & 0xFF), g: UInt8((value >> 8) & 0xFF), b: UInt8(value & 0xFF), a: 255)
        }
        return RGBA(r: UInt8((value >> 24) & 0xFF), g: UInt8((value >> 16) & 0xFF), b: UInt8((value >> 8) & 0xFF), a: UInt8(value & 0xFF))
    }

    private static func parseLayers(_ table: [String: Any], palette: [Character: RGBA], canvas: Int,
                                    problems: inout [String]) -> [String: Layer] {
        var result: [String: Layer] = [:]
        for (name, value) in table {
            guard let spec = value as? [String: Any],
                  let at = spec["at"] as? [Int], at.count == 2,
                  let rows = spec["rows"] as? [String], !rows.isEmpty else {
                problems.append("'\(name)': {\"at\": [x, y], \"rows\": [...]} 형식이어야 함")
                continue
            }
            let width = rows[0].count
            var pixels: [[RGBA?]] = []
            for (index, row) in rows.enumerated() {
                if row.count != width {
                    problems.append("'\(name)' \(index)번째 줄 길이 \(row.count) (첫 줄은 \(width))")
                }
                pixels.append(row.map { symbol -> RGBA? in
                    if symbol == "." { return nil }
                    guard let color = palette[symbol] else {
                        problems.append("'\(name)' \(index)번째 줄: palette에 없는 글자 '\(symbol)'")
                        return nil
                    }
                    return color
                })
            }
            let layer = Layer(x: at[0], y: at[1], pixels: pixels)
            if layer.x < 0 || layer.y < 0 || layer.x + width > canvas || layer.y + rows.count > canvas {
                problems.append("'\(name)'이(가) \(canvas)x\(canvas) 칸을 벗어남 (at \(at), 크기 \(width)x\(rows.count))")
            }
            result[name] = layer
        }
        return result
    }
}
