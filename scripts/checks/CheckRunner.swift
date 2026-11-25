import Foundation

/// This object is responsible for running every check suite against the app's model code
/// and exiting non-zero on any failure. Built by `scripts/verify.sh`.
@main
struct CheckRunner {
    static func main() {
        let skins = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/Skins")
        let check = Checker()
        SkinChecks.run(check)
        #if canImport(AppKit) && !PORTABLE_CHECKS
        MacSkinChecks.run(check, skinsDirectory: skins)
        #else
        // 맥 밖(윈도우·리눅스)은 공통 PNG 해독기로 같은 스킨 확인. 맥에서도 -D PORTABLE_CHECKS로 이 경로를 돌릴 수 있음
        SkinChecks.runLibrary(check, skinsDirectory: skins, loader: DecodedFrame.load, pixels: { $0.pixels })
        #endif
        WorldChecks.run(check)
        BehaviorChecks.run(check)
        FeatureChecks.run(check)
        SkillChecks.run(check)
        FocusChecks.run(check)
        ChaseChecks.run(check)
        CeilingChecks.run(check)
        PlayChecks.run(check)
        SpaceChecks.run(check)
        EntranceChecks.run(check)
        TypingChecks.run(check)
        TrainChecks.run(check)
        PrankChecks.run(check)
        MoodChecks.run(check)
        MenuChecks.run(check)
        CollectionChecks.run(check)
        AffectionChecks.run(check)
        HabitatChecks.run(check)
        SettingsChecks.run(check)
        SceneChecks.run(check)
        CanvasChecks.run(check)
        StageArtChecks.run(check)
        ThrowAimChecks.run(check)
        AgentSignalChecks.run(check)
        NoticePileChecks.run(check)
        HeadTrackerChecks.run(check, skinsDirectory: skins)
        AppMenuChecks.run(check, skinsDirectory: skins)

        print("\n\(check.total - check.failures)/\(check.total) passed")
        exit(check.failures == 0 ? 0 : 1)
    }
}
