// swift-tools-version: 5.9
import PackageDescription

// Sources/DeskPet/Core: 운영체제를 모르는 펫 행동·월드 코드 (Foundation만 씀)
// Sources/DeskPet/Mac: macOS 껍데기 (AppKit·SpriteKit). Sources/DeskPet/Windows: 윈도우 껍데기 (Win32)
#if os(macOS)
let package = Package(
    name: "DeskPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DeskPet",
            targets: ["DeskPet"]
        ),
        // 캐릭터 제작 도구 (리그 → 스킨, 이미지 → 도트 초안). 생성 모델 호출 없음
        .executable(
            name: "SpriteForge",
            targets: ["SpriteForge"]
        )
    ],
    targets: [
        // 공통 코드와 맥 껍데기를 한 모듈로 묶음 (접근 제어자 없이 그대로 씀)
        .executableTarget(
            name: "DeskPet",
            path: "Sources/DeskPet",
            sources: ["Core", "Mac"]
        ),
        .executableTarget(
            name: "SpriteForge",
            path: "Tools/SpriteForge"
        )
    ]
)
#elseif os(Windows)
// 윈도우판: 공통 코드 + Win32 껍데기 (2단계 진행 중, Controller/WINDOWS_PORT.md)
let package = Package(
    name: "DeskPet",
    products: [
        .executable(
            name: "DeskPet",
            targets: ["DeskPet"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DeskPet",
            path: "Sources/DeskPet",
            sources: ["Core", "Windows"]
        )
    ]
)
#else
// 다른 운영체제에서는 공통 코드만 빌드해 이식 준비 상태를 확인함
let package = Package(
    name: "DeskPet",
    targets: [
        .target(
            name: "DeskPetCore",
            path: "Sources/DeskPet/Core"
        )
    ]
)
#endif
