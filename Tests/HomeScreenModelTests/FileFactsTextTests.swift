import Foundation
import Testing
@testable import HomeScreenModel

/// The words follow the Media UI Iconography style guide (D, E); `_` in an expected string is its non-breaking space.
@Suite struct FileFactsTextTests {
    private func nb(_ s: String) -> String { s.replacingOccurrences(of: "_", with: "\u{00A0}") }

    @Test func namesVideoClassesByTheLongSide() {
        func r(_ w: Int, _ h: Int) -> String? { FileFactsText.resolution(FileFacts(width: w, height: h, codec: "HEVC")) }
        #expect(r(1920, 1080) == "FHD")
        #expect(r(1920, 800) == "FHD")   // a scope film keeps its width's class
        #expect(r(1280, 720) == "HD")
        #expect(r(2560, 1440) == "QHD")
        #expect(r(3840, 2160) == "UHD")   // 3840 is UHD, not 4K
        #expect(r(4096, 2160) == "4K")
        #expect(r(6144, 3240) == "6K")
        #expect(r(1080, 1920) == "FHD")   // portrait
        #expect(r(640, 480) == "SD")
        #expect(r(7680, 4320) == "8K")
    }

    @Test func photoResolutionIsItsPixels() {
        #expect(FileFactsText.resolution(FileFacts(width: 4032, height: 3024)) == "4032 × 3024")
        #expect(FileFactsText.resolution(FileFacts()) == nil)
    }

    @Test func ratesAreNotRounded() {
        #expect(FileFactsText.rate(23.976023) == "23.976")
        #expect(FileFactsText.rate(29.97003) == "29.97")
        #expect(FileFactsText.rate(59.94006) == "59.94")
        #expect(FileFactsText.rate(25) == "25")
    }

    @Test func streamLine() {
        let f = FileFacts(width: 3840, height: 2160, duration: 60, codec: "HEVC", fps: 25, transfer: .hlg)
        #expect(FileFactsText.stream(f) == "UHD · 25p · HEVC · HLG")
        #expect(FileFactsText.stream(FileFacts(codec: "H.264", fps: 23.976)) == "23.976p · H.264")
        #expect(FileFactsText.stream(FileFacts(width: 1920, height: 1080, fps: 60, transfer: .sdr)) == "FHD · 60p")
        #expect(FileFactsText.stream(FileFacts()) == nil)
    }

    @Test func exposureLine() {
        let f = FileFacts(exposure: 1.0 / 250, aperture: 2.8, iso: 400, focalLength: 24, exposureBias: -0.33)
        #expect(FileFactsText.exposureLine(f) == nb("1/250 · f/2.8 · ISO_400 · 24_mm · \u{2212}0.3_EV"))
        #expect(FileFactsText.shutter(0.5) == nb("0.5_s"))
        #expect(FileFactsText.shutter(2) == "2\u{2033}")
        #expect(FileFactsText.shutter(1.0 / 3) == "1/3")
        #expect(FileFactsText.bias(1) == nb("+1_EV"))
        #expect(FileFactsText.exposureLine(FileFacts(aperture: 1.8)) == "f/1.8")
        #expect(FileFactsText.exposureLine(FileFacts(exposureBias: 0)) == nil)
        #expect(FileFactsText.exposureLine(FileFacts()) == nil)
    }

    @Test func cameraWithoutARepeatedMake() {
        #expect(FileFactsText.camera(make: "Canon", model: "Canon EOS R5") == "Canon EOS R5")
        #expect(FileFactsText.camera(make: "SONY", model: "ILCE-7M4") == "SONY ILCE-7M4")
        #expect(FileFactsText.camera(make: "NIKON CORPORATION", model: "NIKON Z 6_2") == "NIKON Z 6_2")
        #expect(FileFactsText.camera(make: "Apple", model: "iPhone 15 Pro") == "Apple iPhone 15 Pro")
        #expect(FileFactsText.camera(make: nil, model: nil) == nil)
        let f = FileFacts(camera: "Sony ILCE-7M4", lens: "FE 24-70mm F2.8 GM II")
        #expect(FileFactsText.cameraLine(f) == "Sony ILCE-7M4 · FE 24-70mm F2.8 GM II")
    }

    @Test func sizesAreDecimalWithOneDecimalUnderAHundred() {
        #expect(FileFactsText.size(850) == nb("850_B"))
        #expect(FileFactsText.size(4_200_000) == nb("4.2_MB"))
        #expect(FileFactsText.size(24_612_908) == nb("24.6_MB"))
        #expect(FileFactsText.size(148_200_000) == nb("148_MB"))
        #expect(FileFactsText.size(3_214_551_040) == nb("3.2_GB"))
        #expect(FileFactsText.size(999_999) == nb("1.0_MB"))
    }

    @Test func lengthAndPosterLine() {
        #expect(FileFactsText.length(48) == "0:48")
        #expect(FileFactsText.length(750) == "12:30")
        #expect(FileFactsText.length(3730) == "1:02:10")
        let video = FileFacts(width: 1920, height: 1080, duration: 60, codec: "HEVC", fps: 60)
        #expect(FileFactsText.posterLine(video, bytes: 1_200_000_000) == nb("FHD · 60p · HEVC · 1.2_GB"))
        let photo = FileFacts(width: 4032, height: 3024, exposure: 1.0 / 250, aperture: 2.8, iso: 400)
        #expect(FileFactsText.posterLine(photo, bytes: 3_000_000) == nb("1/250 · f/2.8 · ISO_400"))
        #expect(FileFactsText.posterLine(FileFacts(width: 800, height: 600), bytes: 3_000_000) == nb("800 × 600 · 3.0_MB"))
        #expect(FileFactsText.posterLine(nil, bytes: 5) == nil)
        #expect(FileFactsText.posterLine(FileFacts(), bytes: 5) == nil)
    }

    @Test func badgesAndMegapixels() {
        #expect(FileFactsText.megapixels(FileFacts(width: 6000, height: 4000)) == nb("24_MP"))
        #expect(FileFactsText.megapixels(FileFacts(width: 3264, height: 2448)) == nb("8_MP"))
        #expect(FileFactsText.megapixels(FileFacts(width: 2560, height: 1440)) == nb("3.7_MP"))
        // A photo: the format first, then the size (guide F3); a video: the class, then its colour or its rate.
        #expect(FileFactsText.badges(FileFacts(width: 6000, height: 4000), format: "arw") == ["RAW", nb("24_MP")])
        let hlg = FileFacts(width: 3840, height: 2160, codec: "HEVC", fps: 25, transfer: .hlg)
        #expect(FileFactsText.badges(hlg, format: "MOV") == ["UHD", "HLG"])
        let sdr = FileFacts(width: 1920, height: 1080, codec: "HEVC", fps: 59.94, transfer: .sdr)
        #expect(FileFactsText.badges(sdr, format: "MP4") == ["FHD", "59.94p"])
        #expect(FileFactsText.badges(nil, format: "JPG").isEmpty)
        #expect(FileFactsText.videoLineWithBadges(FileFacts(codec: "H.264"), bytes: 1_150_000_000) == nb("H.264 · 1.1_GB"))
    }
}
