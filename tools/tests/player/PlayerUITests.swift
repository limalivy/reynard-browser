import XCTest

@MainActor
final class PlayerUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.limalivy.reynard-player-tests")
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait; app.terminate(); app.launch() }
    private func seconds() -> Int {
        let label = app.staticTexts["videoPlayer.time"].label
        let value = label.components(separatedBy: " / ").first ?? ""
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
    private func open(_ sample: String) {
        let cell = app.cells["sample." + sample]
        XCTAssertTrue(cell.waitForExistence(timeout: 10)); cell.tap()
        XCTAssertTrue(app.buttons["videoPlayer.playPause"].waitForExistence(timeout: 10))
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in seconds() >= 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 15), .completed, app.debugDescription)
        XCTAssertFalse(app.activityIndicators["videoPlayer.loading"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = sample; shot.lifetime = .keepAlways; add(shot)
    }
    private func checkSeekAndFullscreen(_ sample: String) {
        open(sample)
        app.buttons["videoPlayer.playPause"].tap()
        XCTAssertTrue(["Play", "播放"].contains(app.buttons["videoPlayer.playPause"].label))
        app.sliders["videoPlayer.seek"].adjust(toNormalizedSliderPosition: 0.5)
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in seconds() >= 12 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sought], timeout: 8), .completed)
        let position = seconds()
        app.buttons["videoPlayer.fullscreen"].tap()
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            let window = app.windows.firstMatch.frame
            let surface = app.otherElements["videoPlayer.surface"].frame
            return window.width > window.height && abs(surface.width - window.width) < 1 && abs(surface.height - window.height) < 1 && app.buttons["videoPlayer.fullscreen"].isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed, app.debugDescription)
        XCTAssertGreaterThanOrEqual(seconds(), position - 1)
        let full = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); full.name = "fullscreen"; full.lifetime = .keepAlways; add(full)
        app.buttons["videoPlayer.fullscreen"].tap()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.windows.firstMatch.frame.height > app.windows.firstMatch.frame.width }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 8), .completed)
        XCTAssertTrue(app.buttons["videoPlayer.close"].isHittable)
        XCTAssertGreaterThanOrEqual(seconds(), position - 1)
        app.buttons["videoPlayer.close"].tap()
        XCTAssertTrue(app.cells["sample." + sample].waitForExistence(timeout: 5))
    }
    func testMP4PlaybackSeekAndFullscreen() { checkSeekAndFullscreen("MP4") }
    func testWebMPlaybackSeekAndFullscreen() { checkSeekAndFullscreen("WebM") }
    func testHLSMergedVideoPlays() { open("HLS merged") }
    func testMKVPlays() { open("MKV") }
    func testWebMPlays() { open("WebM") }
    func testInvalidFileShowsError() {
        app.cells["sample.Invalid"].tap()
        XCTAssertTrue(app.staticTexts["videoPlayer.message"].waitForExistence(timeout: 15), app.debugDescription)
    }
}
