import UIKit
import AVFoundation

@main
final class PlayerTestApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--reset-player-state"), let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = PlayerSamplesController()
        window?.makeKeyAndVisible()
        return true
    }
}

final class PlayerSamplesController: UITableViewController {
    let samples = [("MP4", "player-mp4.mp4"), ("HLS merged", "player-hls.mp4"),
                   ("MKV", "player-mkv.mkv"), ("WebM", "player-webm.webm"),
                   ("Invalid", "player-invalid.mp4"), ("Portrait", "player-portrait.mp4")]
    override func viewDidLoad() { super.viewDidLoad(); title = "Video player tests" }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { samples.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = samples[indexPath.row].0
        cell.accessibilityIdentifier = "sample." + samples[indexPath.row].0
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let name = samples[indexPath.row].1
        let url = Bundle.main.bundleURL.appendingPathComponent(name)
        present(VideoPlayerViewController(fileURL: url), animated: true)
        if ProcessInfo.processInfo.arguments.contains("--interrupt-playback") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification,
                    object: AVAudioSession.sharedInstance(),
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
            }
        }
    }
}
