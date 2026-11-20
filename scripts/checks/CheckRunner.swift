import Foundation

/// This object is responsible for running every check suite against the app's model code
/// and exiting non-zero on any failure. Built by `scripts/verify.sh`.
@main
struct CheckRunner {
    static func main() {
        let skins = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets/Skins")
        let check = Checker()
        SkinChecks.run(check, skinsDirectory: skins)
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

        print("\n\(check.total - check.failures)/\(check.total) passed")
        exit(check.failures == 0 ? 0 : 1)
    }
}
