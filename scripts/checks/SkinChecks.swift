import Foundation

/// This object is responsible for checking skin pictures the way the app loads them, on any platform:
/// the pixel rules, the portable PNG decoder, and every real skin folder through a platform `loader`.
enum SkinChecks {
    static func run(_ check: Checker) {
        check.section("스캐너")
        // 플랫폼 없이 픽셀 배열만으로: 4x3 그림의 맨 위 줄 오른쪽 두 칸
        var rgba = [UInt8](repeating: 0, count: 4 * 3 * 4)
        for column in [2, 3] { rgba[column * 4 + 3] = 255 }
        check.expect(SpriteAlphaScanner.scan(SpritePixels(width: 4, height: 3, rgba: rgba)) == .visible(CGRect(x: 2, y: 2, width: 2, height: 1)),
                     "픽셀 배열(위쪽 줄부터)도 같은 규칙")
        check.expect(SpriteAlphaScanner.scan(SpritePixels(width: 4, height: 3, rgba: [])) == .unreadable, "모자란 픽셀은 읽지 못함")

        check.section("PNG 해독")
        // 2x2 팔레트(빨강·투명 파랑) + 위 줄 필터 없음, 아래 줄 Up 필터
        let palette = PNGDecoder.decode(TinyPNG.make(width: 2, height: 2, bitDepth: 8, colorType: 3,
                                                     rows: [[0, 0, 1], [2, 1, 255]],
                                                     palette: [255, 0, 0, 0, 0, 255], transparency: [255, 0]))
        check.expect(palette?.rgba == [255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 255, 0, 255, 0, 0, 255],
                     "팔레트·tRNS·Up 필터", "\(palette?.rgba ?? [])")
        // 1비트 회색 3픽셀 (1, 0, 1)
        let gray = PNGDecoder.decode(TinyPNG.make(width: 3, height: 1, bitDepth: 1, colorType: 0, rows: [[0, 0b1010_0000]]))
        check.expect(gray?.rgba == [255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255], "1비트 회색", "\(gray?.rgba ?? [])")
        // RGBA 2픽셀: Sub 필터와 Paeth 필터
        let sub = PNGDecoder.decode(TinyPNG.make(width: 2, height: 2, bitDepth: 8, colorType: 6,
                                                 rows: [[1, 10, 20, 30, 255, 5, 5, 5, 0], [4, 1, 1, 1, 0, 0, 0, 0, 0]]))
        check.expect(sub?.rgba == [10, 20, 30, 255, 15, 25, 35, 255, 11, 21, 31, 255, 15, 25, 35, 255],
                     "Sub·Paeth 필터", "\(sub?.rgba ?? [])")
        check.expect(PNGDecoder.decode(Data([1, 2, 3])) == nil, "PNG가 아니면 nil")
        // 고정 허프만 블록: zlib이 "aaaaaaaaaa"를 압축한 결과
        check.expect(Inflater.inflate(zlib: [0x78, 0x9C, 0x4B, 0x4C, 0x84, 0x01, 0x00, 0x14, 0xE1, 0x03, 0xCB]) == Array(repeating: 97, count: 10),
                     "고정 허프만 + 겹치는 복사")
    }

    /// 실제 스킨 폴더를 플랫폼 로더로 읽어 확인. pixels는 로드된 프레임의 픽셀 (빈 프레임 확인용)
    static func runLibrary<Frame: Equatable>(_ check: Checker, skinsDirectory: URL,
                                             loader: @escaping (URL) -> LoadedSprite<Frame>?,
                                             pixels: (Frame) -> SpritePixels?) {
        check.section("스킨 로드")
        let library = SkinLibrary(directory: skinsDirectory, loader: loader)
        check.expect(!library.names.isEmpty, "스킨 폴더에서 스킨을 읽음", skinsDirectory.path)

        for name in library.names {
            guard let skin = library.skins[name] else { continue }
            let counts = [Facing.north, .south, .east, .west].map { "\($0.rawValue)=\(skin.walkTextures[$0]?.count ?? 0)" }
            let body = skin.body
            print("  · \(name): walk[\(counts.joined(separator: " "))] blank=\(skin.blankFrameCount) "
                + "body=\(Int(body.width))x\(Int(body.height)) foot=\(Int(body.footInset)) center=\(body.centerX)")

            check.expect(!skin.walkTextures.isEmpty, "\(name): 걷기 프레임 있음")
            let leftovers = (skin.walkTextures.values.flatMap { $0 } + skin.actionTextures.values.flatMap { $0 })
                .filter { pixels($0).map(SpriteAlphaScanner.scan) == .blank }
            check.expect(leftovers.isEmpty, "\(name): 로드된 프레임에 빈 프레임 없음", "\(leftovers.count)")
            check.expect(body.width > 4 && body.width <= 48 && body.height > 4 && body.footInset >= 0,
                         "\(name): 몸 크기 측정", "\(body)")
        }

        // Boy·Girl 원본 시트는 모두 왼쪽(west)을 보는 단일 방향 시트
        for name in ["Boy", "Girl"] {
            guard let skin = library.skins[name] else { continue }
            check.expect(skin.walkTextures.keys.sorted { $0.rawValue < $1.rawValue } == [.west] && skin.walkTextures[.west]?.count == 8,
                         "\(name): 걷기는 왼쪽 방향 8프레임만", "\(skin.walkTextures.mapValues(\.count))")
            check.expect(skin.sprite(for: .walk, facing: .west, elapsed: 0)?.mirrored == false
                         && skin.sprite(for: .walk, facing: .east, elapsed: 0)?.mirrored == true,
                         "\(name): 오른쪽으로 걸을 때는 왼쪽 걷기를 반전 (뒷걸음질 방지)")
            check.expect(skin.sprite(for: .idle, facing: .west, elapsed: 0)?.mirrored == false
                         && skin.sprite(for: .idle, facing: .east, elapsed: 0)?.mirrored == true,
                         "\(name): 대기 자세도 같은 규칙")
            check.expect(skin.sprite(for: .climb, facing: .east, elapsed: 0)?.mirrored == true,
                         "\(name): 뒷모습이 없어 벽 쪽을 향한 걷기로 오름")
            check.expect(skin.supports(.act) && skin.actionTextures[.west]?.count == 5, "\(name): 공격 5프레임")
            check.expect(skin.blankFrameCount == 0, "\(name): 빈 프레임 파일 정리됨", "\(skin.blankFrameCount)")
        }
        // 원본 스킨도 매달리기 4프레임 (SpriteForge hang으로 추가)
        for name in ["Boy", "Girl", "Goblin", "Radish"] {
            guard let skin = library.skins[name] else { continue }
            let hang = skin.hangTextures.values.first ?? []
            check.expect(hang.count == 4, "\(name): 매달리기 4프레임", "\(hang.count)")
            check.expect(skin.sprite(for: .hang, facing: .west, elapsed: 0)?.texture == hang.first
                         && skin.sprite(for: .hang, facing: .east, elapsed: 0)?.mirrored == false,
                         "\(name): 매달릴 때 Hang 프레임을 반전 없이 사용")
        }
        // 남의 시트(Pixel Adventure)로 만든 스킨: 오른쪽 보는 옆모습, 옆 벽 오르기, 원래 속도에 가까운 프레임 간격
        for name in ["NinjaFrog", "MaskDude", "PinkMan", "VirtualGuy"] {
            guard let skin = library.skins[name] else {
                check.expect(false, "\(name): 스킨 있음")
                continue
            }
            let counts = [skin.idleLoopTextures, skin.walkTextures, skin.jumpTextures, skin.hangTextures, skin.climbTextures]
                .map { $0[.east]?.count ?? 0 }
            check.expect(counts == [11, 12, 1, 4, 5], "\(name): 대기11·걷기12·점프1·매달리기4·오르기5 (오른쪽)", "\(counts)")
            check.expect(skin.sprite(for: .walk, facing: .west, elapsed: 0)?.mirrored == true, "\(name): 왼쪽은 반전")
            check.expect(skin.sprite(for: .climb, facing: .east, elapsed: 0)?.texture == skin.climbTextures[.east]?.first
                         && skin.sprite(for: .climb, facing: .west, elapsed: 0)?.mirrored == true,
                         "\(name): 벽 쪽을 향한 옆 오르기 프레임")
            check.expect(abs(skin.cycleDuration(of: .idle, facing: .east) - 11 * 0.06) < 0.001, "\(name): 대기 프레임 간격 0.06초")
            check.expect(skin.blankFrameCount == 0 && !skin.supports(.act), "\(name): 빈 프레임 없음, 공격 없음")
        }
        // Sunny Land: 오른쪽 보는 여우(뒷모습 오르기·매달리기, 구르기 공격)와 왼쪽 보는 주머니쥐·개구리
        if let foxy = library.skins["Foxy"] {
            let counts = [foxy.idleLoopTextures[.east], foxy.walkTextures[.east], foxy.climbTextures[.north],
                          foxy.hangTextures[.north], foxy.sleepTextures[.east], foxy.actionTextures[.east]].map { $0?.count ?? 0 }
            check.expect(counts == [4, 6, 4, 4, 1, 4], "Foxy: 대기4·걷기6·오르기4(뒷모습)·매달리기4·잠1·구르기4", "\(counts)")
            check.expect(foxy.supports(.act) && foxy.sprite(for: .climb, facing: .west, elapsed: 0)?.mirrored == false,
                         "Foxy: 구르기로 대결, 뒷모습 오르기는 반전 없음")
        } else {
            check.expect(false, "Foxy: 스킨 있음")
        }
        for name in ["Opossum", "Froggy"] {
            check.expect(library.skins[name]?.sprite(for: .walk, facing: .east, elapsed: 0)?.mirrored == true
                         && library.skins[name]?.sprite(for: .walk, facing: .west, elapsed: 0)?.mirrored == false,
                         "\(name): 왼쪽 보는 원본, 오른쪽은 반전")
        }
        // Ninja Adventure: 위에서 내려다본 16px 그림의 왼쪽 열을 2배로. 오르기·매달리기는 뒷모습
        for name in ["NinjaGreen", "Skeleton", "Samurai", "Princess", "Knight"] {
            guard let skin = library.skins[name] else {
                check.expect(false, "\(name): 스킨 있음")
                continue
            }
            check.expect(skin.walkTextures[.west]?.count == 4 && skin.climbTextures[.north]?.count == 4
                         && skin.hangTextures[.north]?.count == 4 && skin.supports(.act),
                         "\(name): 걷기4(왼쪽)·뒷모습 오르기4·매달리기4·공격", "\(skin.walkTextures.mapValues(\.count))")
            check.expect(skin.body.height >= 24 && skin.body.height <= 36, "\(name): 2배로 키워 다른 캐릭터와 비슷한 키", "\(skin.body)")
        }
        // DungeonTileset II: 프레임마다 따로 있는 파일을 이어 붙임 (대기4·달리기4, 오른쪽)
        for name in ["Elf", "Wizard", "Lizard", "Dwarf", "BigDemon"] {
            guard let skin = library.skins[name] else {
                check.expect(false, "\(name): 스킨 있음")
                continue
            }
            check.expect(skin.idleLoopTextures[.east]?.count == 4 && skin.walkTextures[.east]?.count == 4
                         && skin.sprite(for: .walk, facing: .west, elapsed: 0)?.mirrored == true,
                         "\(name): 대기4·걷기4 (오른쪽, 왼쪽은 반전)")
            check.expect(skin.sprite(for: .hang, facing: .east, elapsed: 0) != nil && skin.sprite(for: .climb, facing: .east, elapsed: 0) != nil,
                         "\(name): 없는 동작(매달리기·오르기)은 대체 그림으로")
        }
        let skills = ["Boy": SkillStyle.slashJump, "NinjaFrog": .slashJump, "VirtualGuy": .flameRocket, "PinkMan": .bigJump, "Girl": .slashJump, "Goblin": .poleVault, "Radish": .flameRocket, "Nabi": .bigJump, "Bolt": .flameRocket]
        // 공개 저장소에 없는 캐릭터(scripts/private-skins.txt)는 있을 때만 확인
        let aims = ["NinjaFrog": 0.15, "BigDemon": -0.15, "Bolt": 0.1, "Knight": 0.0, "Nabi": 0.0]
        check.expect(aims.allSatisfy { library.skins[$0.key]?.aimBias == $0.value }, "캐릭터별 던지기 성격 (닌자 +, 덩치 큰 악마 −)",
                     "\(aims.keys.map { "\($0)=\(library.skins[$0]?.aimBias ?? -9)" })")
        for (name, style) in skills where library.skins[name] != nil || !["Boy", "Girl", "Goblin", "Radish"].contains(name) {
            check.expect(library.skins[name]?.skillStyle == style, "\(name): 스킬 \(style.rawValue)")
        }
        if let goblin = library.skins["Goblin"] {
            check.expect(goblin.sprite(for: .walk, facing: .west, elapsed: 0)?.mirrored == true,
                         "Goblin: 서쪽 달리기는 동쪽 이미지를 반전")
            check.expect(goblin.sprite(for: .climb, facing: .east, elapsed: 0)?.texture == goblin.walkTextures[.north]?.first,
                         "Goblin: 등반은 뒷모습")
            check.expect(goblin.supports(.act) && goblin.cycleDuration(of: .act, facing: .west) > 0,
                         "Goblin: 공격 애니메이션 있음")
        }

        // SpriteForge가 만든 스킨: 모든 동작 칸이 채워지고 앱이 그 칸을 씀
        if let nabi = library.skins["Nabi"] {
            let counts = [nabi.idleLoopTextures, nabi.walkTextures, nabi.jumpTextures, nabi.hangTextures,
                          nabi.sleepTextures, nabi.actionTextures].map { $0[.west]?.count ?? 0 }
            check.expect(counts == [6, 8, 1, 4, 2, 4], "Nabi: 대기6·걷기8·점프1·매달리기4·잠2·공격4", "\(counts)")
            check.expect(nabi.sprite(for: .hang, facing: .west, elapsed: 0)?.texture == nabi.hangTextures[.west]?.first,
                         "Nabi: 매달릴 때 Hang 프레임 사용")
            check.expect(nabi.sprite(for: .sleep, facing: .east, elapsed: 0)?.mirrored == true,
                         "Nabi: 잠도 방향 규칙대로 반전")
            check.expect(nabi.sprite(for: .airborne, facing: .west, elapsed: 0)?.texture == nabi.jumpTextures[.west]?.first,
                         "Nabi: 공중에서 Jump 프레임 사용")
            check.expect(nabi.blankFrameCount == 0, "Nabi: 빈 프레임 없음")
        }
    }
}

/// This object is responsible for standing in for a platform texture in checks on systems without one:
/// one decoded skin picture, compared by identity like a texture object.
final class DecodedFrame: Equatable {
    let pixels: SpritePixels

    init(pixels: SpritePixels) {
        self.pixels = pixels
    }

    static func load(_ url: URL) -> LoadedSprite<DecodedFrame>? {
        PNGDecoder.decode(contentsOf: url).map { LoadedSprite(frame: DecodedFrame(pixels: $0), pixels: $0) }
    }

    static func == (lhs: DecodedFrame, rhs: DecodedFrame) -> Bool {
        lhs === rhs
    }
}

/// This object is responsible for building tiny uncompressed PNG files for decoder checks
/// (stored deflate blocks, so no compressor is needed; CRCs are zero because the decoder skips them).
enum TinyPNG {
    /// rows: 줄마다 필터 바이트 + 줄 바이트
    static func make(width: Int, height: Int, bitDepth: UInt8, colorType: UInt8, rows: [[UInt8]],
                     palette: [UInt8] = [], transparency: [UInt8] = []) -> Data {
        var png: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        func chunk(_ type: String, _ body: [UInt8]) {
            png += bigEndian(body.count) + Array(type.utf8) + body + [0, 0, 0, 0]
        }
        chunk("IHDR", bigEndian(width) + bigEndian(height) + [bitDepth, colorType, 0, 0, 0])
        if !palette.isEmpty { chunk("PLTE", palette) }
        if !transparency.isEmpty { chunk("tRNS", transparency) }
        let raw = rows.flatMap { $0 }
        let length = UInt16(raw.count)
        let stored: [UInt8] = [1, UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
        chunk("IDAT", [0x78, 0x01] + stored + raw + [0, 0, 0, 0])
        chunk("IEND", [])
        return Data(png)
    }

    private static func bigEndian(_ value: Int) -> [UInt8] {
        [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
}
