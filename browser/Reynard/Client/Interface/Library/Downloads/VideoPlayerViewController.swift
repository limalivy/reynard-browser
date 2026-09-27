import UIKit
import AVFoundation
import MobileVLCKit

/// Local playback and controls are shared by the system and compatible decoders.
final class VideoPlayerViewController: UIViewController, VLCMediaPlayerDelegate, UIGestureRecognizerDelegate, UIAdaptivePresentationControllerDelegate {
    private let fileURL: URL
    private let progressStore = VideoPlaybackProgressStore()
    private let surface = UIView()
    private let videoView = VideoRenderingView()
    private var videoLayer: AVPlayerLayer { videoView.playerLayer }
    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var vlcPlayer: VLCMediaPlayer?
    private var timer: Timer?
    private var hideTask: DispatchWorkItem?
    private var feedbackTask: DispatchWorkItem?
    private var stopped = false
    private var ready = false
    private var failed = false
    private var ended = false
    private var wantsPlayback = true
    private var restoredPosition = false
    private var isSeeking = false
    private var pendingSeekTime: Double?
    private var seekStartedAt: TimeInterval = 0
    private var seekGeneration = 0
    private var lastSaveTime: TimeInterval = 0
    private var speed: Float = 1
    private var muted = false
    private var repeats = false
    private var fillsScreen = false
    private var controlsVisible = true
    private var locked = false
    private var lockedOrientation: UIInterfaceOrientation?
    private var panStart: Double = 0
    private var resumeAfterSeek = false
    private var wasIdleTimerDisabled = false
    private var fullscreenController: VideoFullscreenViewController?
    private var surfaceConstraints: [NSLayoutConstraint] = []
    private var previousOrientation: UIInterfaceOrientation = .portrait

    private let header = UIStackView()
    private let footer = UIStackView()
    private let playButton = UIButton(type: .system)
    private let backwardButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let speedButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)
    private let unlockButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()
    private let feedbackLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        preferredContentSize = CGSize(width: 720, height: 480)
        let saved = UserDefaults.standard.float(forKey: "VideoPlayer.speed")
        if Self.speeds.contains(saved) { speed = saved }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private static let speeds: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        lockedOrientation.map(videoOrientationMask) ?? .allButUpsideDown
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        buildPlayerView()
        mountSurface(in: view)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(playbackEnded), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        center.addObserver(self, selector: #selector(playbackFailed), name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        center.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(leavingForeground), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(accessibilityChanged), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        startPlayback()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateControls() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentationController?.delegate = self
        if fullscreenController == nil { previousOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateVideoLayout()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { stopPlayback() }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { stopPlayback() }

    deinit {
        timer?.invalidate(); hideTask?.cancel(); feedbackTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        player.pause(); vlcPlayer?.delegate = nil; vlcPlayer?.stop()
    }

    private func configure(_ button: UIButton, image: String?, title: String, id: String, action: Selector) {
        if let image { button.setImage(UIImage(systemName: image), for: .normal) }
        button.tintColor = .white
        button.accessibilityLabel = NSLocalizedString(title, comment: "")
        button.accessibilityIdentifier = "videoPlayer." + id
        button.addTarget(self, action: action, for: .touchUpInside)
        button.addTarget(self, action: #selector(controlTouched), for: .touchDown)
        button.addTarget(self, action: #selector(controlTouchCancelled), for: [.touchCancel, .touchUpOutside])
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func buildPlayerView() {
        view.backgroundColor = .black
        surface.backgroundColor = .black
        surface.accessibilityIdentifier = "videoPlayer.surface"
        videoView.backgroundColor = .black
        videoView.clipsToBounds = true
        videoView.accessibilityIdentifier = "videoPlayer.video"
        videoView.isAccessibilityElement = true
        videoView.accessibilityLabel = fileURL.lastPathComponent
        videoView.accessibilityTraits = .image
        videoView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: NSLocalizedString("Play or Pause", comment: ""), target: self, selector: #selector(accessibleToggle)),
            UIAccessibilityCustomAction(name: NSLocalizedString("Forward 10 Seconds", comment: ""), target: self, selector: #selector(accessibleForward)),
            UIAccessibilityCustomAction(name: NSLocalizedString("Back 10 Seconds", comment: ""), target: self, selector: #selector(accessibleBackward)),
        ]
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = player
        configure(closeButton, image: "xmark", title: "Close", id: "close", action: #selector(closePlayer))
        configure(fullscreenButton, image: "arrow.up.left.and.arrow.down.right", title: "Full Screen", id: "fullscreen", action: #selector(toggleFullscreen))
        configure(playButton, image: "pause.fill", title: "Pause", id: "playPause", action: #selector(togglePlayback))
        configure(backwardButton, image: "gobackward.10", title: "Back 10 Seconds", id: "backward", action: #selector(skipBackward))
        configure(forwardButton, image: "goforward.10", title: "Forward 10 Seconds", id: "forward", action: #selector(skipForward))
        configure(speedButton, image: nil, title: "Playback Speed", id: "speed", action: #selector(chooseSpeed))
        configure(muteButton, image: "speaker.wave.2.fill", title: "Mute", id: "mute", action: #selector(toggleMute))
        configure(moreButton, image: "ellipsis", title: "Playback Options", id: "options", action: #selector(showOptions))
        configure(lockButton, image: "lock.open", title: "Lock Controls", id: "lock", action: #selector(toggleLock))
        configure(unlockButton, image: "lock.fill", title: "Unlock Controls", id: "unlock", action: #selector(toggleLock))
        unlockButton.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        unlockButton.layer.cornerRadius = 12
        unlockButton.isHidden = true
        speedButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        speedButton.setTitleColor(.white, for: .normal)
        let titleLabel = UILabel()
        titleLabel.text = fileURL.lastPathComponent
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for child in [closeButton, titleLabel, moreButton, fullscreenButton] { header.addArrangedSubview(child) }
        header.alignment = .center; header.spacing = 4
        slider.accessibilityLabel = NSLocalizedString("Playback Position", comment: "")
        slider.accessibilityIdentifier = "videoPlayer.seek"
        slider.addTarget(self, action: #selector(beginSeeking), for: .touchDown)
        slider.addTarget(self, action: #selector(seekingChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(finishSeeking), for: [.touchUpInside, .touchUpOutside])
        slider.addTarget(self, action: #selector(cancelSeeking), for: .touchCancel)
        slider.tintColor = .white
        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.accessibilityIdentifier = "videoPlayer.time"
        let leftSpace = UIView(), rightSpace = UIView()
        let transport = UIStackView(arrangedSubviews: [muteButton, leftSpace, backwardButton, playButton, forwardButton, rightSpace, speedButton, lockButton])
        leftSpace.widthAnchor.constraint(equalTo: rightSpace.widthAnchor).isActive = true
        transport.alignment = .center; transport.spacing = 4
        footer.axis = .vertical; footer.spacing = 2
        for child in [slider, timeLabel, transport] { footer.addArrangedSubview(child) }
        for chrome in [header, footer] {
            chrome.backgroundColor = UIColor.black.withAlphaComponent(0.65)
            chrome.isLayoutMarginsRelativeArrangement = true
            chrome.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            chrome.layer.cornerRadius = 12
        }
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "videoPlayer.message"
        feedbackLabel.textColor = .white
        feedbackLabel.textAlignment = .center
        feedbackLabel.numberOfLines = 0
        feedbackLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        feedbackLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        feedbackLabel.layer.cornerRadius = 10; feedbackLabel.clipsToBounds = true
        feedbackLabel.accessibilityIdentifier = "videoPlayer.feedback"
        feedbackLabel.isHidden = true
        spinner.color = .white; spinner.hidesWhenStopped = true
        spinner.accessibilityIdentifier = "videoPlayer.loading"
        for child in [videoView, header, footer, messageLabel, spinner, feedbackLabel, unlockButton] {
            child.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(child)
        }
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: surface.topAnchor), videoView.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: surface.leadingAnchor), videoView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            header.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            messageLabel.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: surface.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            feedbackLabel.centerXAnchor.constraint(equalTo: surface.centerXAnchor), feedbackLabel.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            feedbackLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 180), feedbackLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            unlockButton.trailingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            unlockButton.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        let single = UITapGestureRecognizer(target: self, action: #selector(tappedVideo))
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTappedVideo(_:)))
        double.numberOfTapsRequired = 2; single.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(scrubbedVideo(_:)))
        pan.maximumNumberOfTouches = 1
        for gesture in [single, double, pan] { gesture.delegate = self; videoView.addGestureRecognizer(gesture) }
    }

    private func mountSurface(in container: UIView) {
        NSLayoutConstraint.deactivate(surfaceConstraints)
        surface.removeFromSuperview()
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        surfaceConstraints = [surface.topAnchor.constraint(equalTo: container.topAnchor), surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                              surface.leadingAnchor.constraint(equalTo: container.leadingAnchor), surface.trailingAnchor.constraint(equalTo: container.trailingAnchor)]
        NSLayoutConstraint.activate(surfaceConstraints)
        container.layoutIfNeeded(); updateVideoLayout()
    }

    private var duration: Double {
        let value = vlcPlayer.map { Double($0.media?.length.intValue ?? 0) / 1000 } ?? player.currentItem?.duration.seconds ?? 0
        return value.isFinite && value > 0 ? value : 0
    }
    private var position: Double {
        if let pendingSeekTime { return pendingSeekTime }
        if ended { return duration }
        let value = vlcPlayer.map { Double($0.time.intValue) / 1000 } ?? player.currentTime().seconds
        return value.isFinite ? max(0, value) : 0
    }
    private var canSeek: Bool { ready && !failed && duration > 0 && (vlcPlayer?.isSeekable ?? true) }

    private func startPlayback() {
        stopped = false; failed = false; ended = false; ready = false; restoredPosition = false
        wantsPlayback = true; pendingSeekTime = nil; seekGeneration += 1
        itemObservation = nil; vlcPlayer?.delegate = nil; vlcPlayer?.stop(); vlcPlayer?.drawable = nil; vlcPlayer = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        videoLayer.player = player; videoLayer.isHidden = false
        videoView.compatibleCanvas.isHidden = true
        messageLabel.text = nil; spinner.startAnimating(); setControlsVisible(true)
        NotificationCenter.default.post(name: .localVideoPlaybackWillStart, object: self)
        activateAudio()
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else { showError(); return }
        if ["mkv", "webm", "avi", "flv", "wmv", "ts", "mts", "m2ts", "ogv", "m3u8"].contains(fileURL.pathExtension.lowercased()) {
            startCompatiblePlayer(); return
        }
        let item = AVPlayerItem(url: fileURL)
        item.audioTimePitchAlgorithm = .timeDomain
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.vlcPlayer == nil, item === self.player.currentItem else { return }
                switch item.status {
                case .readyToPlay: self.ready = true; self.spinner.stopAnimating(); self.restorePositionIfNeeded(); self.applyPlaybackIntent()
                case .failed: self.startCompatiblePlayer()
                default: break
                }
            }
        }
        player.isMuted = muted
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func startCompatiblePlayer() {
        guard !stopped, vlcPlayer == nil else { return }
        let current = position
        itemObservation = nil; player.pause(); player.replaceCurrentItem(with: nil)
        videoLayer.player = nil; videoLayer.isHidden = true
        videoView.compatibleCanvas.isHidden = false
        let compatible = VLCMediaPlayer()
        compatible.delegate = self; compatible.drawable = videoView.compatibleCanvas; compatible.media = VLCMedia(url: fileURL)
        vlcPlayer = compatible; ready = false
        if current > 0 { pendingSeekTime = current; restoredPosition = false }
        compatible.play()
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        guard !stopped, let compatible = vlcPlayer,
              notification.object as? VLCMediaPlayer === compatible else { return }
        if compatible.state == .error || compatible.media?.state == .error { showError(); return }
        if compatible.state == .ended {
            if duration <= 0 || !ready { showError() } else { reachedEnd() }
            return
        }
        if !ready && compatible.hasVideoOut && duration > 0 {
            ready = true; spinner.stopAnimating(); restorePositionIfNeeded(); applyPlaybackIntent(); updateVideoLayout()
        }
        updateControls()
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        guard !stopped, let compatible = vlcPlayer,
              notification.object as? VLCMediaPlayer === compatible else { return }
        if let target = pendingSeekTime {
            let actual = Double(compatible.time.intValue) / 1000
            if abs(actual - target) < 1 || (compatible.isPlaying && CACurrentMediaTime() - seekStartedAt > 2) { pendingSeekTime = nil }
        }
        mediaPlayerStateChanged(notification)
    }

    private func restorePositionIfNeeded() {
        guard !restoredPosition, duration > 0 else { return }
        restoredPosition = true
        if let saved = pendingSeekTime ?? progressStore.position(for: fileURL, duration: duration) {
            seek(to: saved)
            showFeedback(String(format: NSLocalizedString("Resumed at %@", comment: ""), Self.timeText(saved)))
        }
    }

    private func activateAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* The decoder can continue using the current session. */ }
    }

    private func applyPlaybackIntent() {
        guard !stopped, ready, !failed else { return }
        if let compatible = vlcPlayer {
            compatible.audio?.isMuted = muted
            compatible.rate = speed
            if wantsPlayback { compatible.play() } else { compatible.pause() }
        } else {
            player.isMuted = muted
            if wantsPlayback { player.playImmediately(atRate: speed) } else { player.pause() }
        }
        UIApplication.shared.isIdleTimerDisabled = wantsPlayback
        if wantsPlayback { scheduleAutoHide() } else { setControlsVisible(true) }
        updateControls()
    }

    private func pausePlayback() {
        wantsPlayback = false; resumeAfterSeek = false
        player.pause(); vlcPlayer?.pause()
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        savePosition(); setControlsVisible(true); updateControls()
    }

    private func savePosition() {
        guard ready, !failed else { return }
        if ended { progressStore.remove(fileURL) }
        else { progressStore.save(position, duration: duration, for: fileURL) }
        lastSaveTime = CACurrentMediaTime()
    }

    private func stopPlayback() {
        guard !stopped else { return }
        savePosition(); stopped = true; wantsPlayback = false
        timer?.invalidate(); timer = nil; hideTask?.cancel(); feedbackTask?.cancel()
        itemObservation = nil; seekGeneration += 1
        player.pause(); player.replaceCurrentItem(with: nil)
        vlcPlayer?.delegate = nil; vlcPlayer?.stop(); vlcPlayer?.drawable = nil; vlcPlayer = nil
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func showError() {
        guard !failed else { return }
        failed = true; wantsPlayback = false; ready = false
        player.pause(); vlcPlayer?.pause(); spinner.stopAnimating()
        messageLabel.text = NSLocalizedString("This video could not be played. The file may be incomplete or unsupported.", comment: "")
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        setControlsVisible(true); updateControls()
    }

    private func reachedEnd() {
        guard !ended else { return }
        ended = true; wantsPlayback = false; pendingSeekTime = nil
        progressStore.remove(fileURL); spinner.stopAnimating()
        UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled
        if repeats { replay() }
        else { setControlsVisible(true); updateControls() }
    }

    private func replay() {
        ended = false; wantsPlayback = true; progressStore.remove(fileURL)
        if let compatible = vlcPlayer, compatible.state == .stopped || compatible.state == .ended {
            compatible.delegate = nil; compatible.stop(); compatible.drawable = nil; vlcPlayer = nil
            ready = false; restoredPosition = true; pendingSeekTime = 0
            activateAudio(); startCompatiblePlayer()
        } else { seek(to: 0); activateAudio(); applyPlaybackIntent() }
    }

    private func updateControls() {
        guard !stopped else { return }
        if let compatible = vlcPlayer, !ready && !failed && compatible.hasVideoOut && duration > 0 {
            ready = true; spinner.stopAnimating(); restorePositionIfNeeded(); applyPlaybackIntent()
            return
        }
        let current = isSeeking ? duration * Double(slider.value) : position
        if !isSeeking && duration > 0 { slider.value = Float(min(1, current / duration)) }
        slider.isEnabled = canSeek; backwardButton.isEnabled = canSeek; forwardButton.isEnabled = canSeek
        slider.accessibilityValue = Self.timeText(current) + " / " + Self.timeText(duration)
        timeLabel.text = slider.accessibilityValue
        videoView.accessibilityValue = slider.accessibilityValue
        let title = failed ? "Retry" : ended ? "Replay" : wantsPlayback ? "Pause" : "Play"
        let icon = failed || ended ? "arrow.counterclockwise" : wantsPlayback ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: icon), for: .normal)
        playButton.accessibilityLabel = NSLocalizedString(title, comment: "")
        speedButton.setTitle(String(format: "%g×", speed), for: .normal)
        speedButton.accessibilityValue = String(format: "%g×", speed)
        muteButton.setImage(UIImage(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), for: .normal)
        muteButton.accessibilityLabel = NSLocalizedString(muted ? "Unmute" : "Mute", comment: "")
        if ready && !isSeeking && CACurrentMediaTime() - lastSaveTime >= 5 { savePosition() }
    }

    private static func timeText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        let seconds = Int(value)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func seek(to value: Double) {
        guard canSeek else { return }
        let target = min(max(0, value), duration)
        ended = false; pendingSeekTime = target; seekStartedAt = CACurrentMediaTime(); seekGeneration += 1
        if let compatible = vlcPlayer { compatible.position = Float(target / duration) }
        else {
            let generation = seekGeneration
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.seekGeneration == generation, !self.stopped else { return }
                    self.pendingSeekTime = nil; self.savePosition(); self.updateControls()
                }
            }
        }
        savePosition(); updateControls()
    }

    @objc private func togglePlayback() {
        if failed { startPlayback(); return }
        if ended { replay(); return }
        if wantsPlayback { pausePlayback() }
        else { wantsPlayback = true; activateAudio(); applyPlaybackIntent() }
    }
    @objc private func skipBackward() { skip(-10) }
    @objc private func skipForward() { skip(10) }
    private func skip(_ seconds: Double) {
        guard canSeek else { return }
        seek(to: position + seconds); showFeedback(seconds > 0 ? "+10 s" : "−10 s"); scheduleAutoHide()
    }
    @objc private func accessibleToggle() -> Bool { guard !locked else { return false }; togglePlayback(); return true }
    @objc private func accessibleForward() -> Bool { guard !locked else { return false }; skipForward(); return canSeek }
    @objc private func accessibleBackward() -> Bool { guard !locked else { return false }; skipBackward(); return canSeek }

    @objc private func beginSeeking() {
        guard canSeek else { return }
        isSeeking = true; resumeAfterSeek = wantsPlayback; hideTask?.cancel()
        player.pause(); vlcPlayer?.pause()
    }
    @objc private func seekingChanged() {
        if isSeeking { updateControls() }
        else { seek(to: duration * Double(slider.value)); scheduleAutoHide() }
    }
    @objc private func finishSeeking() {
        isSeeking = false; wantsPlayback = resumeAfterSeek
        seek(to: duration * Double(slider.value)); applyPlaybackIntent()
    }
    @objc private func cancelSeeking() {
        isSeeking = false; wantsPlayback = resumeAfterSeek; applyPlaybackIntent()
    }

    @objc private func chooseSpeed() {
        let actions = Self.speeds.map { value in
            UIAlertAction(title: String(format: "%g×", value), style: .default) { [weak self] _ in
                guard let self else { return }
                self.speed = value; UserDefaults.standard.set(value, forKey: "VideoPlayer.speed")
                self.applyPlaybackIntent(); self.updateControls(); self.scheduleAutoHide()
            }
        }
        showMenu(title: "Playback Speed", actions: actions, source: speedButton)
    }

    @objc private func showOptions() {
        let fit = UIAlertAction(title: NSLocalizedString(fillsScreen ? "Fit Video" : "Fill Screen", comment: ""), style: .default) { [weak self] _ in
            guard let self else { return }; self.fillsScreen.toggle(); self.updateVideoLayout(); self.scheduleAutoHide()
        }
        let loop = UIAlertAction(title: NSLocalizedString(repeats ? "Stop Repeating" : "Repeat Video", comment: ""), style: .default) { [weak self] _ in
            guard let self else { return }; self.repeats.toggle(); self.showFeedback(NSLocalizedString(self.repeats ? "Repeat Video" : "Stop Repeating", comment: "")); self.scheduleAutoHide()
        }
        let restart = UIAlertAction(title: NSLocalizedString("Play from Beginning", comment: ""), style: .default) { [weak self] _ in
            self?.replay()
        }
        showMenu(title: "Playback Options", actions: [fit, loop, restart], source: moreButton)
    }

    private func showMenu(title: String, actions: [UIAlertAction], source: UIView) {
        hideTask?.cancel()
        let menu = UIAlertController(title: NSLocalizedString(title, comment: ""), message: nil, preferredStyle: .actionSheet)
        actions.forEach(menu.addAction)
        menu.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in self?.scheduleAutoHide() })
        menu.popoverPresentationController?.sourceView = source
        menu.popoverPresentationController?.sourceRect = source.bounds
        (fullscreenController ?? self).present(menu, animated: true)
    }

    @objc private func toggleMute() { muted.toggle(); player.isMuted = muted; vlcPlayer?.audio?.isMuted = muted; updateControls(); scheduleAutoHide() }

    private func setControlsVisible(_ visible: Bool) {
        hideTask?.cancel(); controlsVisible = visible && !locked
        header.isHidden = !controlsVisible; footer.isHidden = !controlsVisible
        if controlsVisible { scheduleAutoHide() }
    }
    private func scheduleAutoHide() {
        hideTask?.cancel()
        guard controlsVisible, wantsPlayback, ready, !isSeeking, !failed, !UIAccessibility.isVoiceOverRunning else { return }
        let task = DispatchWorkItem { [weak self] in self?.setControlsVisible(false) }
        hideTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: task)
    }
    private func showFeedback(_ text: String) {
        feedbackTask?.cancel(); feedbackLabel.text = text; feedbackLabel.isHidden = false
        let task = DispatchWorkItem { [weak self] in self?.feedbackLabel.isHidden = true }
        feedbackTask = task; DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
    @objc private func tappedVideo() { guard !locked else { return }; setControlsVisible(!controlsVisible) }
    @objc private func controlTouched() { hideTask?.cancel() }
    @objc private func controlTouchCancelled() { scheduleAutoHide() }
    @objc private func doubleTappedVideo(_ gesture: UITapGestureRecognizer) {
        guard !locked else { return }
        let fraction = gesture.location(in: videoView).x / max(1, videoView.bounds.width)
        if fraction < 0.35 { skipBackward() }
        else if fraction > 0.65 { skipForward() }
        else { togglePlayback() }
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard !locked, !UIAccessibility.isVoiceOverRunning else { return false }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = pan.velocity(in: videoView)
            return canSeek && abs(velocity.x) > abs(velocity.y)
        }
        return true
    }
    @objc private func scrubbedVideo(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStart = position; resumeAfterSeek = wantsPlayback; isSeeking = true; hideTask?.cancel()
            player.pause(); vlcPlayer?.pause()
        case .changed:
            let target = min(max(0, panStart + Double(gesture.translation(in: videoView).x / max(1, videoView.bounds.width)) * min(120, duration)), duration)
            slider.value = Float(target / duration); updateControls(); showFeedback(Self.timeText(target) + " / " + Self.timeText(duration))
        case .ended:
            let target = duration * Double(slider.value)
            isSeeking = false; wantsPlayback = resumeAfterSeek; seek(to: target); applyPlaybackIntent()
        case .cancelled, .failed:
            isSeeking = false; wantsPlayback = resumeAfterSeek; applyPlaybackIntent()
        default: break
        }
    }

    @objc private func toggleLock() {
        locked.toggle(); unlockButton.isHidden = !locked; isModalInPresentation = locked
        lockedOrientation = locked ? surface.window?.windowScene?.interfaceOrientation : nil
        fullscreenController?.lockedOrientation = lockedOrientation
        if #available(iOS 16.0, *) { setNeedsUpdateOfSupportedInterfaceOrientations(); fullscreenController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
        setControlsVisible(!locked)
    }

    private func updateVideoLayout() {
        videoView.compatibleSize = vlcPlayer?.videoSize ?? .zero
        videoView.fillsScreen = fillsScreen
        videoView.setNeedsLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
        videoLayer.setNeedsLayout()
        videoLayer.layoutIfNeeded()
        CATransaction.commit()
        videoView.layoutIfNeeded()
    }

    @objc private func playbackEnded(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem, item === player.currentItem { reachedEnd() }
    }
    @objc private func playbackFailed(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem, item === player.currentItem { startCompatiblePlayer() }
    }
    @objc private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        pausePlayback()
    }
    @objc private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        pausePlayback()
    }
    @objc private func leavingForeground() {
        pausePlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    @objc private func accessibilityChanged() { setControlsVisible(true) }

    @objc private func closePlayer() {
        guard !locked else { return }
        stopPlayback()
        if let controller = fullscreenController {
            controller.dismiss(animated: false) { [weak self] in
                guard let self else { return }
                self.fullscreenController = nil; self.mountSurface(in: self.view)
                self.restoreOrientation(); self.dismiss(animated: true)
            }
        } else { dismiss(animated: true) }
    }

    @objc private func toggleFullscreen() {
        guard !locked else { return }
        if fullscreenController != nil { exitFullscreen(); return }
        previousOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        let size = vlcPlayer?.videoSize ?? player.currentItem?.presentationSize ?? .zero
        let orientation: UIInterfaceOrientation = size.height > size.width ? .portrait : .landscapeRight
        let controller = VideoFullscreenViewController(orientation: orientation)
        fullscreenController = controller
        controller.onLayout = { [weak self] in self?.updateVideoLayout() }
        controller.loadViewIfNeeded(); mountSurface(in: controller.view)
        fullscreenButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        fullscreenButton.accessibilityLabel = NSLocalizedString("Exit Full Screen", comment: "")
        setControlsVisible(true); present(controller, animated: true)
    }

    private func restoreOrientation() {
        if #available(iOS 16.0, *), let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: videoOrientationMask(previousOrientation)))
        }
    }
    private func exitFullscreen() {
        guard let controller = fullscreenController else { return }
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.fullscreenController = nil; self.mountSurface(in: self.view)
            self.fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            self.fullscreenButton.accessibilityLabel = NSLocalizedString("Full Screen", comment: "")
            self.restoreOrientation(); self.setControlsVisible(true)
        }
    }
}

private final class VideoRenderingView: UIView {
    let playerLayer = AVPlayerLayer()
    let compatibleCanvas = UIView()
    var compatibleSize = CGSize.zero
    var fillsScreen = false
    override init(frame: CGRect) {
        super.init(frame: frame); layer.addSublayer(playerLayer)
        compatibleCanvas.isUserInteractionEnabled = false
        compatibleCanvas.isHidden = true
        addSubview(compatibleCanvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin(); CATransaction.setDisableActions(true); playerLayer.frame = bounds; CATransaction.commit()
        compatibleCanvas.bounds = CGRect(origin: .zero, size: bounds.size)
        compatibleCanvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
        var scale: CGFloat = 1
        if fillsScreen && compatibleSize.width > 0 && compatibleSize.height > 0 && bounds.width > 0 && bounds.height > 0 {
            let horizontal = bounds.width / compatibleSize.width
            let vertical = bounds.height / compatibleSize.height
            scale = max(horizontal, vertical) / min(horizontal, vertical)
        }
        // Transform the existing drawable so fit/fill also updates an already-paused frame.
        compatibleCanvas.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

private func videoOrientationMask(_ orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
    switch orientation {
    case .landscapeLeft: return .landscapeLeft
    case .landscapeRight: return .landscapeRight
    case .portraitUpsideDown: return .portraitUpsideDown
    default: return .portrait
    }
}

private final class VideoFullscreenViewController: UIViewController {
    var onLayout: (() -> Void)?
    var lockedOrientation: UIInterfaceOrientation?
    private let initialOrientation: UIInterfaceOrientation
    private var requestedInitialOrientation = false
    init(orientation: UIInterfaceOrientation) {
        initialOrientation = orientation
        super.init(nibName: nil, bundle: nil); modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { lockedOrientation.map(videoOrientationMask) ?? .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { initialOrientation }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !requestedInitialOrientation else { return }
        requestedInitialOrientation = true
        if #available(iOS 16.0, *), let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: videoOrientationMask(initialOrientation)))
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
}
