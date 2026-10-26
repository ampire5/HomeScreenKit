import Foundation
import Testing
@testable import HomeScreenModel

@Suite struct FileFactsTextTests {
    @Test func namesVideoResolutionsByTheShorterSide() {
        func r(_ w: Int, _ h: Int) -> String? { FileFactsText.resolution(FileFacts(width: w, height: h, codec: "HEVC")) }
        #expect(r(1920, 1080) == "1080p")
        #expect(r(1920, 800) == "1080p")   // a wide film keeps its width's name
        #expect(r(1280, 720) == "720p")
        #expect(r(2560, 1440) == "1440p")
        #expect(r(3840, 2160) == "4K")
        #expect(r(1080, 1920) == "1080p")   // portrait
        #expect(r(640, 480) == "480p")
        #expect(r(7680, 4320) == "8K")
    }

    @Test func photoResolutionIsItsPixels() {
        #expect(FileFactsText.resolution(FileFacts(width: 4032, height: 3024)) == "4032 × 3024")
        #expect(FileFactsText.resolution(FileFacts()) == nil)
    }

    @Test func streamLine() {
        let f = FileFacts(width: 1920, height: 1080, duration: 60, codec: "HEVC", fps: 59.94, hdr: true)
        #expect(FileFactsText.stream(f) == "1080p · HEVC · 59.94 fps · HDR")
        #expect(FileFactsText.stream(FileFacts(codec: "H.264", fps: 23.976)) == "H.264 · 23.98 fps")
        #expect(FileFactsText.stream(FileFacts(width: 3840, height: 2160, fps: 60)) == "4K · 60 fps")
        #expect(FileFactsText.stream(FileFacts()) == nil)
    }

    @Test func exposureLine() {
        let f = FileFacts(exposure: 1.0 / 250, aperture: 2.8, iso: 400, focalLength: 24)
        #expect(FileFactsText.exposureLine(f) == "1/250 · f/2.8 · ISO 400 · 24 mm")
        #expect(FileFactsText.shutter(0.5) == "0.5 s")
        #expect(FileFactsText.shutter(2) == "2 s")
        #expect(FileFactsText.shutter(1.0 / 3) == "1/3")
        #expect(FileFactsText.exposureLine(FileFacts(aperture: 1.8)) == "f/1.8")
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

    @Test func lengthAndPosterLine() {
        #expect(FileFactsText.length(750) == "12:30")
        #expect(FileFactsText.length(3730) == "1:02:10")
        let video = FileFacts(width: 1920, height: 1080, duration: 60, codec: "HEVC", fps: 60)
        #expect(FileFactsText.posterLine(video, bytes: 1_200_000_000) == "1080p · HEVC · 60 fps · 1.2 GB")
        let photo = FileFacts(width: 4032, height: 3024, exposure: 1.0 / 250, aperture: 2.8, iso: 400)
        #expect(FileFactsText.posterLine(photo, bytes: 3_000_000) == "1/250 · f/2.8 · ISO 400")
        #expect(FileFactsText.posterLine(FileFacts(width: 800, height: 600), bytes: 3_000_000) == "800 × 600 · 3 MB")
        #expect(FileFactsText.posterLine(nil, bytes: 5) == nil)
        #expect(FileFactsText.posterLine(FileFacts(), bytes: 5) == nil)
    }
}
