import UIKit
import AVFoundation
import MobileVLCKit

/// Owns playback independently of Quick Look and the web page's media element.
final class VideoPlayerViewController: UIViewController, VLCMediaPlayerDelegate {
    private let fileURL: URL
    private let surface = UIView()
    private let videoView = UIView()
    private let videoLayer = AVPlayerLayer()
    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var vlcPlayer: VLCMediaPlayer?
    private var timer: Timer?
    private var stopped = false
    private var isSeeking = false
    private var pendingSeekTime: Double?
    private var ended = false
    private var fullscreenController: VideoFullscreenViewController?
    private var surfaceConstraints: [NSLayoutConstraint] = []
    private var previousOrientation: UIInterfaceOrientation = .portrait

    private let playButton = UIButton(type: .system)
    private let fullscreenButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(fileURL: URL) {
        self.fileURL = fileURL
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        preferredContentSize = CGSize(width: 720, height: 480)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildPlayerView()
        mountSurface(in: view)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackEnded),
                                               name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackFailed),
                                               name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
        startPlayback()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateControls() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if fullscreenController == nil { previousOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoLayer.frame = videoView.bounds
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true { stopPlayback() }
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
        player.pause()
        vlcPlayer?.stop()
    }

    private func buildPlayerView() {
        surface.backgroundColor = .black
        surface.accessibilityIdentifier = "videoPlayer.surface"
        videoView.backgroundColor = .black
        videoView.layer.addSublayer(videoLayer)
        videoLayer.videoGravity = .resizeAspect
        videoLayer.player = player

        let titleLabel = UILabel()
        titleLabel.text = fileURL.lastPathComponent
        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = NSLocalizedString("Close", comment: "")
        closeButton.accessibilityIdentifier = "videoPlayer.close"
        closeButton.addTarget(self, action: #selector(closePlayer), for: .touchUpInside)
        fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        fullscreenButton.accessibilityLabel = NSLocalizedString("Full Screen", comment: "")
        fullscreenButton.accessibilityIdentifier = "videoPlayer.fullscreen"
        fullscreenButton.addTarget(self, action: #selector(toggleFullscreen), for: .touchUpInside)
        playButton.accessibilityIdentifier = "videoPlayer.playPause"
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        for button in [closeButton, fullscreenButton, playButton] {
            button.tintColor = .white
            button.widthAnchor.constraint(equalToConstant: 48).isActive = true
            button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
        let header = UIStackView(arrangedSubviews: [closeButton, titleLabel, fullscreenButton])
        header.alignment = .center
        header.spacing = 8
        slider.accessibilityLabel = NSLocalizedString("Playback Position", comment: "")
        slider.accessibilityIdentifier = "videoPlayer.seek"
        slider.addTarget(self, action: #selector(beginSeeking), for: .touchDown)
        slider.addTarget(self, action: #selector(finishSeeking), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        slider.tintColor = .white
        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.accessibilityIdentifier = "videoPlayer.time"
        let progress = UIStackView(arrangedSubviews: [slider, timeLabel])
        progress.axis = .vertical
        progress.spacing = 4
        let controls = UIStackView(arrangedSubviews: [playButton, progress])
        controls.alignment = .center
        controls.spacing = 12

        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.accessibilityIdentifier = "videoPlayer.message"
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.accessibilityIdentifier = "videoPlayer.loading"
        for child in [videoView, header, controls, messageLabel, spinner] {
            child.translatesAutoresizingMaskIntoConstraints = false
            surface.addSubview(child)
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            controls.leadingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: surface.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            videoView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            videoView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -8),
            videoView.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: videoView.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -24),
            spinner.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: videoView.centerYAnchor),
        ])
    }

    private func mountSurface(in container: UIView) {
        NSLayoutConstraint.deactivate(surfaceConstraints)
        surface.removeFromSuperview()
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)
        surfaceConstraints = [surface.topAnchor.constraint(equalTo: container.topAnchor),
                              surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                              surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                              surface.trailingAnchor.constraint(equalTo: container.trailingAnchor)]
        NSLayoutConstraint.activate(surfaceConstraints)
        container.layoutIfNeeded()
        videoLayer.frame = videoView.bounds
    }

    private func startPlayback() {
        NotificationCenter.default.post(name: .localVideoPlaybackWillStart, object: self)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { /* Playback can still proceed without changing an existing session. */ }
        spinner.startAnimating()
        if ["mkv", "webm", "avi", "flv", "wmv", "ts", "mts", "m2ts", "ogv", "m3u8"].contains(fileURL.pathExtension.lowercased()) {
            startCompatiblePlayer()
            return
        }
        let item = AVPlayerItem(url: fileURL)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, !self.stopped, self.vlcPlayer == nil else { return }
                switch item.status {
                case .readyToPlay: self.spinner.stopAnimating(); self.player.play()
                case .failed: self.startCompatiblePlayer()
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func startCompatiblePlayer() {
        guard !stopped, vlcPlayer == nil else { return }
        itemObservation = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        videoLayer.player = nil
        videoLayer.isHidden = true
        let compatible = VLCMediaPlayer()
        compatible.delegate = self
        compatible.drawable = videoView
        compatible.media = VLCMedia(url: fileURL)
        vlcPlayer = compatible
        compatible.play()
    }

    func mediaPlayerStateChanged(_ notification: Notification) {
        // Terminal states may be followed immediately by .stopped, before the timer fires.
        updateControls()
    }

    func mediaPlayerTimeChanged(_ notification: Notification) {
        pendingSeekTime = nil
        updateControls()
    }

    private func stopPlayback() {
        stopped = true
        timer?.invalidate(); timer = nil
        itemObservation = nil
        player.pause(); player.replaceCurrentItem(with: nil)
        vlcPlayer?.delegate = nil
        vlcPlayer?.stop(); vlcPlayer?.drawable = nil; vlcPlayer = nil
    }

    private func updateControls() {
        let current: Double
        let duration: Double
        let playing: Bool
        if let compatible = vlcPlayer {
            // VLC updates its cached time on playback ticks, not while seeking paused video.
            current = pendingSeekTime ?? Double(compatible.time.intValue) / 1000
            duration = Double(compatible.media?.length.intValue ?? 0) / 1000
            playing = compatible.isPlaying
            if compatible.hasVideoOut || compatible.isPlaying || compatible.state == .paused || compatible.state == .ended { spinner.stopAnimating() }
            if compatible.state == .ended { ended = true }
            if compatible.state == .error || compatible.media?.state == .error || (compatible.state == .ended && duration <= 0) {
                spinner.stopAnimating()
                messageLabel.text = NSLocalizedString("This video could not be played. The file may be incomplete or unsupported.", comment: "")
            }
        } else {
            current = player.currentTime().seconds
            duration = player.currentItem?.duration.seconds ?? 0
            playing = player.rate != 0
        }
        let validDuration = duration.isFinite && duration > 0
        slider.isEnabled = validDuration && (vlcPlayer?.isSeekable ?? true)
        if !isSeeking && validDuration { slider.value = Float(max(0, current) / duration) }
        timeLabel.text = "\(Self.timeText(current)) / \(Self.timeText(duration))"
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = NSLocalizedString(playing ? "Pause" : "Play", comment: "")
        videoLayer.frame = videoView.bounds
    }

    private static func timeText(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "--:--" }
        let seconds = Int(value)
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func togglePlayback() {
        if let compatible = vlcPlayer {
            if compatible.isPlaying { compatible.pause() }
            else { if ended { compatible.stop(); ended = false }; compatible.play() }
        } else if player.rate != 0 { player.pause() }
        else {
            if ended { player.seek(to: .zero); ended = false }
            player.play()
        }
        updateControls()
    }

    @objc private func playbackEnded(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem, item === player.currentItem { ended = true; updateControls() }
    }

    @objc private func playbackFailed(_ notification: Notification) {
        if let item = notification.object as? AVPlayerItem, item === player.currentItem { startCompatiblePlayer() }
    }

    @objc private func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        player.pause(); if vlcPlayer?.isPlaying == true { vlcPlayer?.pause() }
    }

    @objc private func beginSeeking() { isSeeking = true }
    @objc private func finishSeeking() {
        if let compatible = vlcPlayer, compatible.isSeekable {
            pendingSeekTime = Double(compatible.media?.length.intValue ?? 0) / 1000 * Double(slider.value)
            compatible.position = slider.value
        }
        else if let duration = player.currentItem?.duration.seconds, duration.isFinite {
            player.seek(to: CMTime(seconds: duration * Double(slider.value), preferredTimescale: 600))
        }
        ended = false; isSeeking = false
        updateControls()
    }

    @objc private func closePlayer() {
        if fullscreenController != nil { exitFullscreen() }
        else { stopPlayback(); dismiss(animated: true) }
    }

    @objc private func toggleFullscreen() {
        if fullscreenController != nil { exitFullscreen(); return }
        previousOrientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        let controller = VideoFullscreenViewController()
        fullscreenController = controller
        controller.onLayout = { [weak self] in self?.videoLayer.frame = self?.videoView.bounds ?? .zero }
        controller.loadViewIfNeeded()
        mountSurface(in: controller.view)
        fullscreenButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .normal)
        fullscreenButton.accessibilityLabel = NSLocalizedString("Exit Full Screen", comment: "")
        present(controller, animated: true)
    }

    private func exitFullscreen() {
        guard let controller = fullscreenController else { return }
        controller.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.fullscreenController = nil
            self.mountSurface(in: self.view)
            self.fullscreenButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            self.fullscreenButton.accessibilityLabel = NSLocalizedString("Full Screen", comment: "")
            if #available(iOS 16.0, *), let scene = self.view.window?.windowScene {
                let mask: UIInterfaceOrientationMask = self.previousOrientation.isLandscape ? .landscape : .portrait
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            }
        }
    }
}

private final class VideoFullscreenViewController: UIViewController {
    var onLayout: (() -> Void)?
    init() { super.init(nibName: nil, bundle: nil); modalPresentationStyle = .fullScreen }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override func viewDidLoad() { super.viewDidLoad(); view.backgroundColor = .black }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if #available(iOS 16.0, *), let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onLayout?() }
}
