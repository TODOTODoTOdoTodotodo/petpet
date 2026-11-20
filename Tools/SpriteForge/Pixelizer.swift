import Foundation

/// This object is responsible for turning a reference picture (e.g. one made in the Gemini app) into a draft rig:
/// removing a plain background, shrinking the character to sprite size, reducing it to a small palette and
/// adding a dark outline. Fully deterministic; the agent then splits the single `body` layer into parts.
struct Pixelizer {
    var targetHeight = 30
    var colorCount = 10
    var flip = false
    var canvas = 48
    var ground = 44
    /// 배경으로 볼 색 거리 (RGB 유클리드)
    var backgroundTolerance = 48.0

    func draftRig(from url: URL, name: String) throws -> [String: Any] {
        let image = try Raster.readImage(url)
        let mask = foregroundMask(image)
        guard let box = boundingBox(mask, width: image.width, height: image.height) else {
            throw ForgeError(description: "캐릭터를 찾지 못함 (배경이 단색인지 확인)")
        }

        // 크기 맞추기: 높이 기준, 가로는 외곽선 자리를 남기고 제한
        let scale = Double(targetHeight) / Double(box.height)
        let width = min(canvas - 6, max(1, Int((Double(box.width) * scale).rounded())))
        let height = targetHeight
        var small: [[RGBA?]] = Array(repeating: Array(repeating: nil, count: width), count: height)
        for ty in 0..<height {
            for tx in 0..<width {
                small[ty][tx] = averageBlock(image, mask: mask, box: box, tx: tx, ty: ty, width: width, height: height)
            }
        }
        if flip { small = small.map { $0.reversed() } }

        let palette = quantize(&small)
        let outlined = addOutline(small, color: palette.darkest)

        // 칸에 놓기: 가로 가운데, 발바닥은 ground 줄
        let finalHeight = outlined.count
        let finalWidth = outlined.first?.count ?? 0
        let at = [(canvas - finalWidth) / 2, max(0, ground + 1 - finalHeight)]
        let symbols = Array("abcdefghijmnopqrstuvwxyz").map(String.init)
        var symbolOf: [RGBA: String] = [:]
        var paletteTable: [String: String] = [:]
        for (index, color) in palette.colors.enumerated() {
            symbolOf[color] = symbols[index]
            paletteTable[symbols[index]] = String(format: "#%02x%02x%02x", color.r, color.g, color.b)
        }
        let rows = outlined.map { row in row.map { $0.flatMap { symbolOf[$0] } ?? "." }.joined() }

        return [
            "name": name,
            "skill": "big_jump",
            "facing": "west",
            "canvas": canvas,
            "palette": paletteTable,
            "layers": ["body": ["at": at, "rows": rows]],
            "_notes": "pixelize 초안. 캐릭터가 왼쪽(west)을 보는지 확인하고, 머리·앞뒤 다리·앞뒤 팔·꼬리를 별도 layers로 나누면 걷기·매달리기 등이 살아남",
        ]
    }

    // MARK: - Steps

    /// 배경 제거: 투명 픽셀이 있으면 알파로, 없으면 가장자리에서 비슷한 색을 퍼뜨려 지움
    private func foregroundMask(_ image: (width: Int, height: Int, pixels: [RGBA])) -> [Bool] {
        let (width, height, pixels) = image
        if pixels.contains(where: { $0.a < 16 }) {
            return pixels.map { $0.a >= 128 }
        }
        var background = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        for x in 0..<width { queue += [x, (height - 1) * width + x] }
        for y in 0..<height { queue += [y * width, y * width + width - 1] }
        let corners = [0, width - 1, (height - 1) * width, height * width - 1].map { pixels[$0] }
        let reference = RGBA(r: UInt8(corners.map { Int($0.r) }.reduce(0, +) / 4),
                             g: UInt8(corners.map { Int($0.g) }.reduce(0, +) / 4),
                             b: UInt8(corners.map { Int($0.b) }.reduce(0, +) / 4), a: 255)
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            guard !background[index], distance(pixels[index], reference) <= backgroundTolerance else { continue }
            background[index] = true
            let x = index % width
            let y = index / width
            if x > 0 { queue.append(index - 1) }
            if x < width - 1 { queue.append(index + 1) }
            if y > 0 { queue.append(index - width) }
            if y < height - 1 { queue.append(index + width) }
        }
        return background.map { !$0 }
    }

    private func boundingBox(_ mask: [Bool], width: Int, height: Int) -> (x: Int, y: Int, width: Int, height: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// 작은 칸 하나에 해당하는 원본 영역의 평균색. 캐릭터 픽셀이 절반 미만이면 투명
    private func averageBlock(_ image: (width: Int, height: Int, pixels: [RGBA]), mask: [Bool],
                              box: (x: Int, y: Int, width: Int, height: Int),
                              tx: Int, ty: Int, width: Int, height: Int) -> RGBA? {
        let x0 = box.x + tx * box.width / width
        let x1 = max(x0 + 1, box.x + (tx + 1) * box.width / width)
        let y0 = box.y + ty * box.height / height
        let y1 = max(y0 + 1, box.y + (ty + 1) * box.height / height)
        var r = 0, g = 0, b = 0, count = 0, total = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                total += 1
                let index = y * image.width + x
                guard mask[index] else { continue }
                let pixel = image.pixels[index]
                r += Int(pixel.r); g += Int(pixel.g); b += Int(pixel.b)
                count += 1
            }
        }
        guard count * 2 >= total, count > 0 else { return nil }
        return RGBA(r: UInt8(r / count), g: UInt8(g / count), b: UInt8(b / count), a: 255)
    }

    /// k-평균으로 색 수를 줄임 (외곽선 색 한 칸은 남겨 둠). 시작점은 서로 먼 색부터 골라 결정론적
    private func quantize(_ grid: inout [[RGBA?]]) -> (colors: [RGBA], darkest: RGBA) {
        let samples = grid.flatMap { $0.compactMap { $0 } }
        let k = max(1, min(colorCount - 1, Set(samples).count))
        guard !samples.isEmpty else { return ([], RGBA(r: 0, g: 0, b: 0, a: 255)) }

        var centers = [samples[samples.count / 2]]
        while centers.count < k {
            let next = samples.max { a, b in
                centers.map { distance($0, a) }.min()! < centers.map { distance($0, b) }.min()!
            }!
            centers.append(next)
        }
        for _ in 0..<10 {
            var sums = Array(repeating: (r: 0, g: 0, b: 0, n: 0), count: k)
            for sample in samples {
                let index = nearest(sample, in: centers)
                sums[index].r += Int(sample.r); sums[index].g += Int(sample.g); sums[index].b += Int(sample.b)
                sums[index].n += 1
            }
            centers = sums.enumerated().map { index, sum in
                sum.n == 0 ? centers[index] : RGBA(r: UInt8(sum.r / sum.n), g: UInt8(sum.g / sum.n), b: UInt8(sum.b / sum.n), a: 255)
            }
        }
        grid = grid.map { row in row.map { $0.map { centers[nearest($0, in: centers)] } } }

        // 외곽선: 가장 어두운 색을 더 어둡게
        let darkestCenter = centers.min { luminance($0) < luminance($1) }!
        let outline = RGBA(r: UInt8(Double(darkestCenter.r) * 0.45), g: UInt8(Double(darkestCenter.g) * 0.45),
                           b: UInt8(Double(darkestCenter.b) * 0.45), a: 255)
        var colors = Array(Set(centers)).sorted { luminance($0) < luminance($1) }
        if !colors.contains(outline) { colors.insert(outline, at: 0) }
        return (colors, outline)
    }

    /// 바깥쪽 1px 외곽선 (상하좌우로 맞닿은 투명 칸)
    private func addOutline(_ grid: [[RGBA?]], color: RGBA) -> [[RGBA?]] {
        let height = grid.count + 2
        let width = (grid.first?.count ?? 0) + 2
        var padded: [[RGBA?]] = Array(repeating: Array(repeating: nil, count: width), count: height)
        for (y, row) in grid.enumerated() { for (x, pixel) in row.enumerated() { padded[y + 1][x + 1] = pixel } }
        var result = padded
        for y in 0..<height {
            for x in 0..<width where padded[y][x] == nil {
                let neighbors = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                if neighbors.contains(where: { nx, ny in nx >= 0 && ny >= 0 && nx < width && ny < height && padded[ny][nx] != nil }) {
                    result[y][x] = color
                }
            }
        }
        return result
    }

    private func distance(_ a: RGBA, _ b: RGBA) -> Double {
        let dr = Double(a.r) - Double(b.r), dg = Double(a.g) - Double(b.g), db = Double(a.b) - Double(b.b)
        return (dr * dr + dg * dg + db * db).squareRoot()
    }

    private func nearest(_ color: RGBA, in centers: [RGBA]) -> Int {
        centers.indices.min { distance(color, centers[$0]) < distance(color, centers[$1]) }!
    }

    private func luminance(_ color: RGBA) -> Double {
        0.299 * Double(color.r) + 0.587 * Double(color.g) + 0.114 * Double(color.b)
    }
}
