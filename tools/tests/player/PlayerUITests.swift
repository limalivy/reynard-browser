import XCTest
import UIKit

@MainActor
final class PlayerUITests: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.limalivy.reynard-player-tests")
    private var video: XCUIElement { app.descendants(matching: .any).matching(identifier: "videoPlayer.video").firstMatch }
    private var play: XCUIElement { app.buttons["videoPlayer.playPause"] }

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.terminate(); app.launchArguments = ["--reset-player-state"]; app.launch()
    }
    private func wait(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, description + "\n" + app.debugDescription)
    }
    private func seconds() -> Int {
        let text = video.value as? String ?? ""
        let value = text.components(separatedBy: " / ").first ?? ""
        return value.split(separator: ":").compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
    }
    private func controls() {
        if !play.exists { video.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap() }
        if !play.exists { XCTAssertTrue(play.waitForExistence(timeout: 5), app.debugDescription) }
        if !play.isHittable { wait("Visible controls become interactive", timeout: 5) { self.play.isHittable } }
    }
    private func open(_ sample: String) {
        let cell = app.cells["sample." + sample]
        XCTAssertTrue(cell.waitForExistence(timeout: 10)); cell.tap()
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        wait("Playback should advance", timeout: 15) { self.seconds() >= 1 }
        XCTAssertFalse(app.activityIndicators["videoPlayer.loading"].exists)
    }
    private func pause() {
        controls()
        if ["Pause", "暂停"].contains(play.label) { play.tap() }
        XCTAssertTrue(["Play", "播放"].contains(play.label))
    }
    private func seekHalfway() {
        pause(); app.sliders["videoPlayer.seek"].adjust(toNormalizedSliderPosition: 0.5)
        wait("Seeking should update the time") { (12...19).contains(self.seconds()) }
        XCTAssertTrue(["Play", "播放"].contains(play.label), "Seeking paused video must stay paused")
    }
    private func screenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func fullscreen() {
        controls(); app.buttons["videoPlayer.fullscreen"].tap()
        wait("Fullscreen should fill the landscape window") {
            let window = self.app.windows.firstMatch.frame
            let surface = self.app.otherElements["videoPlayer.surface"].frame
            return window.width > window.height && abs(surface.width - window.width) < 1 && abs(surface.height - window.height) < 1
        }
    }
    private func checkSeekAndFullscreen(_ sample: String) {
        open(sample); seekHalfway(); let position = seconds()
        fullscreen(); XCTAssertEqual(seconds(), position, accuracy: 1)
        screenshot(sample + " fullscreen")
        app.buttons["videoPlayer.fullscreen"].tap()
        wait("Exit fullscreen restores portrait") { self.app.windows.firstMatch.frame.height > self.app.windows.firstMatch.frame.width }
        XCTAssertEqual(seconds(), position, accuracy: 1)
        app.buttons["videoPlayer.close"].tap()
        XCTAssertTrue(app.cells["sample." + sample].waitForExistence(timeout: 5))
        XCTAssertFalse(video.exists)
    }
    private func checkSpeed(_ sample: String) {
        open(sample); controls(); app.buttons["videoPlayer.speed"].tap(); app.sheets.buttons["2×"].tap()
        let start = seconds(); let clock = Date()
        Thread.sleep(forTimeInterval: 3)
        let delta = Double(seconds() - start); let elapsed = Date().timeIntervalSince(clock)
        XCTAssertGreaterThan(delta / elapsed, 1.4, "The decoder must actually play faster")
        XCTAssertLessThan(delta / elapsed, 2.7)
        pause(); XCTAssertEqual(app.buttons["videoPlayer.speed"].value as? String, "2×")
        let position = seconds(); app.buttons["videoPlayer.speed"].tap(); app.sheets.buttons["0.5×"].tap()
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(seconds(), position, accuracy: 1, "Changing speed must not start paused playback")
    }
    private func checkSkipAndGestures(_ sample: String) {
        open(sample); seekHalfway()
        let start = seconds(); app.buttons["videoPlayer.forward"].tap()
        XCTAssertEqual(seconds(), min(30, start + 10), accuracy: 2)
        app.buttons["videoPlayer.backward"].tap(); XCTAssertEqual(seconds(), start, accuracy: 2)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)).doubleTap()
        XCTAssertEqual(seconds(), max(0, start - 10), accuracy: 2)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)).doubleTap()
        XCTAssertEqual(seconds(), start, accuracy: 2)
        let before = seconds()
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)).press(forDuration: 0.1,
            thenDragTo: video.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.45)))
        XCTAssertGreaterThan(seconds(), before + 5)
        XCTAssertTrue(["Play", "播放"].contains(play.label))
    }
    private func checkReplay(_ sample: String, repeating: Bool = false) {
        open(sample); pause()
        if repeating { app.buttons["videoPlayer.options"].tap(); app.sheets.buttons["Repeat Video"].tap() }
        app.sliders["videoPlayer.seek"].adjust(toNormalizedSliderPosition: 0.97)
        play.tap()
        if repeating {
            wait("Repeat starts from the beginning", timeout: 8) { self.seconds() < 6 }
            controls(); XCTAssertEqual(play.label, "Pause")
        } else {
            wait("End of video shows Replay", timeout: 8) { self.play.exists && self.play.label == "Replay" }
            play.tap(); wait("Replay starts from the beginning") { (0...5).contains(self.seconds()) }
            controls(); XCTAssertEqual(play.label, "Pause")
        }
        XCTAssertFalse(app.staticTexts["videoPlayer.message"].exists)
    }
    private func checkResume(_ sample: String) {
        open(sample); seekHalfway(); let saved = seconds()
        app.buttons["videoPlayer.close"].tap()
        app.terminate(); app.launchArguments = []; app.launch()
        open(sample); pause()
        XCTAssertGreaterThanOrEqual(seconds(), saved - 1)
        XCTAssertLessThan(seconds(), saved + 5)
        app.buttons["videoPlayer.options"].tap(); app.sheets.buttons["Play from Beginning"].tap()
        wait("Start over clears the saved position") { self.seconds() < 5 }
    }

    func testMP4PlaybackSeekAndFullscreen() { checkSeekAndFullscreen("MP4") }
    func testWebMPlaybackSeekAndFullscreen() { checkSeekAndFullscreen("WebM") }
    func testHLSMergedVideoPlays() { open("HLS merged") }
    func testMKVPlays() { open("MKV") }
    func testWebMPlays() { open("WebM") }
    func testMP4PlaybackSpeed() { checkSpeed("MP4") }
    func testWebMPlaybackSpeed() { checkSpeed("WebM") }
    func testMP4SkipAndGestures() { checkSkipAndGestures("MP4") }
    func testWebMSkipAndGestures() { checkSkipAndGestures("WebM") }
    func testMP4ResumeAfterRelaunch() { checkResume("MP4") }
    func testWebMResumeAfterRelaunch() { checkResume("WebM") }
    func testMP4Replay() { checkReplay("MP4") }
    func testWebMReplay() { checkReplay("WebM") }
    func testMP4Repeat() { checkReplay("MP4", repeating: true) }
    func testWebMRepeat() { checkReplay("WebM", repeating: true) }
    func testInvalidFileShowsError() {
        app.cells["sample.Invalid"].tap()
        XCTAssertTrue(app.staticTexts["videoPlayer.message"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.activityIndicators["videoPlayer.loading"].exists)
        XCTAssertEqual(play.label, "Retry")
    }
    func testControlsHideAndScreenLock() {
        open("MP4")
        wait("Playing video hides controls", timeout: 7) { !self.play.exists }
        controls(); pause(); fullscreen(); let before = seconds()
        app.buttons["videoPlayer.lock"].tap()
        XCTAssertTrue(app.buttons["videoPlayer.unlock"].exists); XCTAssertFalse(play.exists)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)).doubleTap()
        XCTAssertEqual(seconds(), before, accuracy: 1)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, app.windows.firstMatch.frame.height)
        app.buttons["videoPlayer.unlock"].tap(); XCTAssertTrue(play.isHittable)
        screenshot("Unlocked controls")
    }
    private func videoBrightness(xFraction: CGFloat = 0.5, yFraction: CGFloat = 0.3) -> Int {
        let frame = video.frame, window = app.windows.firstMatch.frame
        let raw = XCUIScreen.main.screenshot().image
        let picture = UIGraphicsImageRenderer(size: window.size).image { _ in
            raw.draw(in: CGRect(origin: .zero, size: window.size))
        }.cgImage!
        let x = Int((frame.minX + frame.width * xFraction) / window.width * Double(picture.width))
        let y = Int((frame.minY + frame.height * yFraction) / window.height * Double(picture.height))
        let bytes = picture.dataProvider!.data! as Data
        let stride = picture.bitsPerPixel / 8
        let offset = y * picture.bytesPerRow + x * stride
        // Screen pixels are opaque; discard the alpha channel regardless of byte order.
        return bytes[offset..<(offset + stride)].sorted().prefix(3).reduce(0) { $0 + Int($1) }
    }
    private func checkMuteAndFill(_ sample: String) {
        open(sample); pause()
        app.buttons["videoPlayer.mute"].tap(); XCTAssertEqual(app.buttons["videoPlayer.mute"].label, "Unmute")
        app.buttons["videoPlayer.mute"].tap(); XCTAssertEqual(app.buttons["videoPlayer.mute"].label, "Mute")
        XCTAssertLessThan(videoBrightness(), 30, "Fit must leave black bars for this landscape fixture")
        app.buttons["videoPlayer.options"].tap(); app.sheets.buttons["Fill Screen"].tap()
        XCTAssertGreaterThan(videoBrightness(), 80, "Fill must visibly expand even a paused video frame")
        screenshot(sample + " fill")
        fullscreen()
        XCTAssertGreaterThan(videoBrightness(xFraction: 0.03, yFraction: 0.5), 80, "Fill survives rotation")
        app.buttons["videoPlayer.options"].tap(); XCTAssertTrue(app.sheets.buttons["Fit Video"].exists)
        app.sheets.buttons["Fit Video"].tap(); screenshot(sample + " fit")
        XCTAssertLessThan(videoBrightness(xFraction: 0.03, yFraction: 0.5), 30, "Landscape fit restores side bars")
        app.buttons["videoPlayer.fullscreen"].tap()
        wait("Framing restores in portrait") { self.app.windows.firstMatch.frame.height > self.app.windows.firstMatch.frame.width }
        XCTAssertLessThan(videoBrightness(), 30, "Fit must restore the original framing")
    }
    func testMuteAndFillOptions() { checkMuteAndFill("WebM") }
    func testMP4FitAndFill() { checkMuteAndFill("MP4") }
    func testPortraitVideoFullscreenStaysPortrait() {
        open("Portrait"); pause(); app.buttons["videoPlayer.fullscreen"].tap()
        wait("Portrait video uses portrait fullscreen") {
            let window = self.app.windows.firstMatch.frame
            let surface = self.app.otherElements["videoPlayer.surface"].frame
            return window.height > window.width && abs(surface.height - window.height) < 1
        }
        screenshot("Portrait fullscreen")
    }
    func testCloseWhileFullscreen() {
        open("WebM"); pause(); fullscreen(); app.buttons["videoPlayer.close"].tap()
        XCTAssertTrue(app.cells["sample.WebM"].waitForExistence(timeout: 8)); XCTAssertFalse(video.exists)
    }
    func testBackgroundPausesPlayback() {
        open("MP4"); let before = seconds()
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 2); app.activate()
        controls(); XCTAssertEqual(play.label, "Play")
        XCTAssertEqual(seconds(), before, accuracy: 2)
    }
    func testAudioInterruptionPausesPlayback() {
        app.terminate(); app.launchArguments = ["--reset-player-state", "--interrupt-playback"]; app.launch()
        open("WebM")
        wait("Audio interruption pauses playback") { self.play.exists && self.play.label == "Play" }
        let before = seconds(); Thread.sleep(forTimeInterval: 1); XCTAssertEqual(seconds(), before, accuracy: 1)
    }
}
