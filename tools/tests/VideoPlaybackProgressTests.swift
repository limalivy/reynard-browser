import Foundation

@main
struct VideoPlaybackProgressTests {
    static func main() throws {
        let suite = "VideoPlaybackProgressTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("video.mp4")
        try Data(repeating: 1, count: 100).write(to: file)
        let store = VideoPlaybackProgressStore(defaults: defaults)
        precondition(store.position(for: file, duration: 100) == nil)
        store.save(35, duration: 100, for: file)
        precondition(VideoPlaybackProgressStore(defaults: defaults).position(for: file, duration: 100) == 35)
        store.save(.nan, duration: 100, for: file)
        store.save(60, duration: .infinity, for: file)
        precondition(store.position(for: file, duration: 100) == 35)
        precondition(store.position(for: file, duration: 20) == nil)
        let moved = root.appendingPathComponent("new-container")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)
        let destination = moved.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destination)
        precondition(store.position(for: destination, duration: 100) == 35)
        store.save(98, duration: 100, for: file)
        precondition(store.position(for: file, duration: 100) == nil)
        store.save(40, duration: 100, for: file); store.remove(file)
        precondition(store.position(for: file, duration: 100) == nil)
        store.save(40, duration: 100, for: file)
        try Data(repeating: 2, count: 101).write(to: file)
        precondition(store.position(for: file, duration: 100) == nil)
        for index in 0..<205 {
            let item = root.appendingPathComponent("\(index).mp4")
            try Data([1]).write(to: item); store.save(10, duration: 100, for: item)
        }
        precondition(defaults.dictionary(forKey: "VideoPlayer.positions.v1")?.count == 200)
        print("PASS: resume persistence, container moves, completed/replaced files, invalid values and bounded history")
    }
}
