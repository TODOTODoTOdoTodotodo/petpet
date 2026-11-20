import Foundation

/// This object is responsible for decoding a PNG file into top-row-first, straight-alpha RGBA pixels
/// without any platform image library, so non-mac shells (Windows) and the checks read skins
/// exactly like the shared code expects.
/// Supports every color type at 1–16 bits and tRNS transparency; interlaced (Adam7) files return nil.
enum PNGDecoder {
    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    static func decode(contentsOf url: URL) -> SpritePixels? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }

    static func decode(_ data: Data) -> SpritePixels? {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { return nil }

        var header: Header?
        var palette: [UInt8] = []
        var transparency: [UInt8] = []
        var compressed: [UInt8] = []
        var offset = 8
        // 청크: 길이(4) · 종류(4) · 내용 · CRC(4). CRC는 확인하지 않음 (깨진 파일은 해독 단계에서 걸러짐)
        while offset + 8 <= bytes.count {
            let length = Int(bigEndian(bytes, offset))
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            let start = offset + 8
            guard length >= 0, start + length <= bytes.count else { return nil }
            let body = bytes[start..<(start + length)]
            switch type {
            case "IHDR": header = Header(body)
            case "PLTE": palette = Array(body)
            case "tRNS": transparency = Array(body)
            case "IDAT": compressed.append(contentsOf: body)
            case "IEND": offset = bytes.count
            default: break
            }
            offset = start + length + 4
        }

        guard let header, header.interlace == 0,
              let raw = Inflater.inflate(zlib: compressed),
              let rows = unfilter(raw, header: header) else { return nil }
        return expand(rows, header: header, palette: palette, transparency: transparency)
    }

    // MARK: - Header

    private struct Header {
        let width: Int
        let height: Int
        let bitDepth: Int
        let colorType: Int
        let interlace: Int

        init?(_ body: ArraySlice<UInt8>) {
            guard body.count >= 13 else { return nil }
            let base = body.startIndex
            width = Int(PNGDecoder.bigEndian(Array(body), 0))
            height = Int(PNGDecoder.bigEndian(Array(body), 4))
            bitDepth = Int(body[base + 8])
            colorType = Int(body[base + 9])
            interlace = Int(body[base + 12])
            guard width > 0, height > 0, width * height <= 16_777_216, channels > 0,
                  [1, 2, 4, 8, 16].contains(bitDepth) else { return nil }
        }

        /// 픽셀당 표본 수 (0 회색, 2 RGB, 3 팔레트, 4 회색+알파, 6 RGBA)
        var channels: Int {
            switch colorType {
            case 0, 3: 1
            case 2: 3
            case 4: 2
            case 6: 4
            default: 0
            }
        }

        var bitsPerPixel: Int { channels * bitDepth }
        var rowBytes: Int { (width * bitsPerPixel + 7) / 8 }
        /// 필터가 왼쪽 픽셀로 보는 바이트 거리 (1바이트 미만 픽셀은 1)
        var filterStep: Int { max(1, bitsPerPixel / 8) }
    }

    private static func bigEndian(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
    }

    // MARK: - Filters

    /// 줄마다 앞의 필터 바이트를 풀어 필터 없는 줄 바이트로 (줄 사이 구분 없이 이어 붙임)
    private static func unfilter(_ raw: [UInt8], header: Header) -> [UInt8]? {
        let stride = header.rowBytes
        let step = header.filterStep
        guard raw.count >= header.height * (stride + 1) else { return nil }
        var out = [UInt8](repeating: 0, count: header.height * stride)
        for row in 0..<header.height {
            let filter = raw[row * (stride + 1)]
            let source = row * (stride + 1) + 1
            let target = row * stride
            for index in 0..<stride {
                let value = raw[source + index]
                let left = index >= step ? Int(out[target + index - step]) : 0
                let up = row > 0 ? Int(out[target - stride + index]) : 0
                let upLeft = row > 0 && index >= step ? Int(out[target - stride + index - step]) : 0
                let predicted: Int
                switch filter {
                case 0: predicted = 0
                case 1: predicted = left
                case 2: predicted = up
                case 3: predicted = (left + up) / 2
                case 4: predicted = paeth(left, up, upLeft)
                default: return nil
                }
                out[target + index] = value &+ UInt8(truncatingIfNeeded: predicted)
            }
        }
        return out
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    // MARK: - Samples → RGBA

    private static func expand(_ rows: [UInt8], header: Header, palette: [UInt8], transparency: [UInt8]) -> SpritePixels? {
        let width = header.width
        let depth = header.bitDepth
        let maxSample = (1 << depth) - 1
        var rgba = [UInt8](repeating: 0, count: width * header.height * 4)

        // 표본 하나 (원래 비트 깊이 값). 16비트는 큰 쪽 바이트가 앞
        func sample(_ row: Int, _ index: Int) -> Int {
            let base = row * header.rowBytes
            switch depth {
            case 8: return Int(rows[base + index])
            case 16: return Int(rows[base + index * 2]) << 8 | Int(rows[base + index * 2 + 1])
            default:
                let bit = index * depth
                let byte = rows[base + bit / 8]
                return Int(byte >> UInt8(8 - depth - bit % 8)) & maxSample
            }
        }
        func scaled(_ value: Int) -> UInt8 {
            depth == 16 ? UInt8(value >> 8) : UInt8(value * 255 / maxSample)
        }
        let key: [Int] = stride(from: 0, to: transparency.count - 1, by: 2).map {
            Int(transparency[$0]) << 8 | Int(transparency[$0 + 1])
        }

        for row in 0..<header.height {
            for column in 0..<width {
                let out = (row * width + column) * 4
                let first = column * header.channels
                var pixel: (UInt8, UInt8, UInt8, UInt8)
                switch header.colorType {
                case 0:
                    let gray = sample(row, first)
                    let alpha: UInt8 = key.first == gray ? 0 : 255
                    pixel = (scaled(gray), scaled(gray), scaled(gray), alpha)
                case 2:
                    let (r, g, b) = (sample(row, first), sample(row, first + 1), sample(row, first + 2))
                    let alpha: UInt8 = key.count >= 3 && key[0] == r && key[1] == g && key[2] == b ? 0 : 255
                    pixel = (scaled(r), scaled(g), scaled(b), alpha)
                case 3:
                    let index = sample(row, first)
                    guard index * 3 + 2 < palette.count else { return nil }
                    let alpha = index < transparency.count ? transparency[index] : 255
                    pixel = (palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2], alpha)
                case 4:
                    let gray = scaled(sample(row, first))
                    pixel = (gray, gray, gray, scaled(sample(row, first + 1)))
                case 6:
                    pixel = (scaled(sample(row, first)), scaled(sample(row, first + 1)),
                             scaled(sample(row, first + 2)), scaled(sample(row, first + 3)))
                default:
                    return nil
                }
                rgba[out] = pixel.0
                rgba[out + 1] = pixel.1
                rgba[out + 2] = pixel.2
                rgba[out + 3] = pixel.3
            }
        }
        return SpritePixels(width: width, height: header.height, rgba: rgba)
    }
}

/// This object is responsible for inflating a zlib stream (RFC 1950 wrapper around RFC 1951 deflate),
/// the compression inside every PNG. Canonical Huffman decoding follows zlib's reference `puff.c`.
struct Inflater {
    private let input: [UInt8]
    private var position = 0
    private var bitBuffer = 0
    private var bitCount = 0
    private var output: [UInt8] = []

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                     35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                      3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                       257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    /// 동적 블록에서 코드 길이 코드의 길이가 오는 순서
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// zlib 머리(2바이트)를 확인하고 풀어낸 바이트. 깨졌으면 nil (Adler-32는 확인하지 않음)
    static func inflate(zlib: [UInt8]) -> [UInt8]? {
        guard zlib.count >= 2, zlib[0] & 0x0F == 8, (Int(zlib[0]) << 8 | Int(zlib[1])) % 31 == 0,
              zlib[1] & 0x20 == 0 else { return nil }
        var inflater = Inflater(input: Array(zlib[2...]))
        return inflater.run()
    }

    private init(input: [UInt8]) {
        self.input = input
    }

    private mutating func run() -> [UInt8]? {
        var last = false
        while !last {
            guard let final = bits(1), let type = bits(2) else { return nil }
            last = final == 1
            switch type {
            case 0: guard stored() else { return nil }
            case 1: guard codes(Self.fixedLiterals, Self.fixedDistances) else { return nil }
            case 2:
                guard let (literals, distances) = dynamicTables(), codes(literals, distances) else { return nil }
            default: return nil
            }
        }
        return output
    }

    private mutating func bits(_ count: Int) -> Int? {
        while bitCount < count {
            guard position < input.count else { return nil }
            bitBuffer |= Int(input[position]) << bitCount
            position += 1
            bitCount += 8
        }
        let value = bitBuffer & ((1 << count) - 1)
        bitBuffer >>= count
        bitCount -= count
        return value
    }

    /// 압축하지 않은 블록: 바이트 경계에 맞춘 길이·보수 뒤 그대로 복사
    private mutating func stored() -> Bool {
        bitBuffer = 0
        bitCount = 0
        guard position + 4 <= input.count else { return false }
        let length = Int(input[position]) | Int(input[position + 1]) << 8
        let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
        position += 4
        guard length == ~complement & 0xFFFF, position + length <= input.count else { return false }
        output.append(contentsOf: input[position..<(position + length)])
        position += length
        return true
    }

    private mutating func codes(_ literals: Huffman, _ distances: Huffman) -> Bool {
        while true {
            guard let symbol = decode(literals) else { return false }
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return true
            } else {
                let index = symbol - 257
                guard index < Self.lengthBase.count, let extra = bits(Self.lengthExtra[index]),
                      let distanceSymbol = decode(distances), distanceSymbol < Self.distanceBase.count,
                      let distanceExtra = bits(Self.distanceExtra[distanceSymbol]) else { return false }
                let length = Self.lengthBase[index] + extra
                let distance = Self.distanceBase[distanceSymbol] + distanceExtra
                guard distance <= output.count else { return false }
                let start = output.count - distance
                // 겹치는 복사(거리 < 길이)도 한 바이트씩이면 반복 무늬가 됨
                for step in 0..<length {
                    output.append(output[start + step])
                }
            }
        }
    }

    private mutating func dynamicTables() -> (Huffman, Huffman)? {
        guard let literalCount = bits(5).map({ $0 + 257 }), let distanceCount = bits(5).map({ $0 + 1 }),
              let codeLengthCount = bits(4).map({ $0 + 4 }), literalCount <= 286, distanceCount <= 30 else { return nil }
        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            guard let length = bits(3) else { return nil }
            codeLengthLengths[Self.codeLengthOrder[index]] = length
        }
        guard let codeLengthCodes = Huffman(lengths: codeLengthLengths) else { return nil }

        var lengths: [Int] = []
        while lengths.count < literalCount + distanceCount {
            guard let symbol = decode(codeLengthCodes) else { return nil }
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:
                guard let previous = lengths.last, let repeats = bits(2) else { return nil }
                lengths.append(contentsOf: repeatElement(previous, count: 3 + repeats))
            case 17:
                guard let repeats = bits(3) else { return nil }
                lengths.append(contentsOf: repeatElement(0, count: 3 + repeats))
            default:
                guard let repeats = bits(7) else { return nil }
                lengths.append(contentsOf: repeatElement(0, count: 11 + repeats))
            }
        }
        guard lengths.count == literalCount + distanceCount, lengths[256] > 0,
              let literals = Huffman(lengths: Array(lengths[0..<literalCount])),
              let distances = Huffman(lengths: Array(lengths[literalCount...])) else { return nil }
        return (literals, distances)
    }

    /// 코드 비트를 하나씩 읽어 길이별 첫 코드와 비교 (puff.c의 decode)
    private mutating func decode(_ table: Huffman) -> Int? {
        var code = 0, first = 0, index = 0
        for length in 1...15 {
            guard let bit = bits(1) else { return nil }
            code |= bit
            let count = table.counts[length]
            if code - count < first {
                return table.symbols[index + (code - first)]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        return nil
    }

    /// This object is responsible for a canonical Huffman code given only each symbol's code length.
    private struct Huffman {
        /// 길이별 코드 수 (0번은 쓰지 않음)
        let counts: [Int]
        /// 길이 순, 같은 길이 안에서는 기호 순
        let symbols: [Int]

        init?(lengths: [Int]) {
            var counts = [Int](repeating: 0, count: 16)
            for length in lengths {
                guard (0...15).contains(length) else { return nil }
                counts[length] += 1
            }
            // 길이가 모두 0이면 코드 없음 (거리 코드가 하나도 안 쓰인 블록에서 가능)
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 {
                offsets[length + 1] = offsets[length] + counts[length]
            }
            var symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
            self.counts = counts
            self.symbols = symbols
        }
    }

    private static let fixedLiterals = Huffman(
        lengths: Array(repeating: 8, count: 144) + Array(repeating: 9, count: 112)
            + Array(repeating: 7, count: 24) + Array(repeating: 8, count: 8)
    )!
    private static let fixedDistances = Huffman(lengths: Array(repeating: 5, count: 30))!
}
