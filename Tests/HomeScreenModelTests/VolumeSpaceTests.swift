import Testing
@testable import HomeScreenModel

@Suite struct VolumeSpaceTests {
    @Test func formatsBinaryDecimalSizes() {
        #expect(VolumeSpace.line(free: 1_200_000_000_000) == "1.2 TB free")
        #expect(VolumeSpace.line(free: 512_000_000) == "512 MB free")
    }

    @Test func nilGivesNoLine() {
        #expect(VolumeSpace.line(free: nil) == nil)
    }

    /// A volume with nothing to say (a share that answers 0) has no line, not "Zero KB free".
    @Test func zeroGivesNoLine() {
        #expect(VolumeSpace.line(free: 0) == nil)
    }
}
