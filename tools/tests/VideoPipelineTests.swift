import Foundation
import GeckoView

@main
struct VideoPipelineTests {
    @MainActor
    static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputRoot = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
        let session = GeckoSession(root: fixture, temporary: outputRoot.appendingPathComponent("transport"))
        let cases: [(String, [String], Double, Bool, Bool)] = [
            ("direct", ["video-11s.mp4"], 11, false, true),
            ("nine", ["video-9s.mp4"], 9, false, false),
            ("ten", ["video-10s.mp4"], 10, false, false),
            ("blob", ["blob:https://fixture.invalid/object"], 11, false, true),
            ("ts", ["hls/ts/index.m3u8"], 11, false, true),
            ("fmp4", ["hls/fmp4/index.m3u8"], 11, false, true),
            ("range", ["hls/range/index.m3u8"], 11, false, true),
            ("aes", ["hls/aes/index.m3u8"], 11, false, true),
            ("audio", ["hls/master.m3u8"], 11, false, true),
            ("discontinuity", ["hls/discontinuity.m3u8"], 12, false, true),
            ("sniff", ["hls/master.m3u8", "hls/fmp4/index.m3u8", "hls/audio/index.m3u8"], 11, true, true),
            ("ambiguous", ["hls/fmp4/index.m3u8", "hls/ts/index.m3u8"], 11, true, false),
            ("mismatch", ["hls/ts/index.m3u8"], 15, true, false),
            ("html", ["index.html"], 11, false, false),
        ]
        for (name, paths, duration, fallback, expected) in cases {
            let sources = paths.map { URL(string: $0.hasPrefix("blob:") ? $0 : "https://fixture.invalid/\($0)")! }
            let work = outputRoot.appendingPathComponent("work-\(name)/result.mp4")
            let job = VideoDownloadTask(session: session, context: VideoDownloadContext(), sources: sources,
                                        duration: duration, isFallback: fallback)
            let result: Bool = await withCheckedContinuation { continuation in
                job.start(output: work, progress: { _ in }, completion: { result in
                    if result {
                        let destination = outputRoot.appendingPathComponent("\(name).mp4")
                        try? FileManager.default.removeItem(at: destination)
                        do { try FileManager.default.copyItem(at: work, to: destination) }
                        catch { fatalError("Missing completed media: \(error)") }
                    }
                    continuation.resume(returning: result)
                })
            }
            guard result == expected else { fatalError("\(name): expected \(expected), got \(result)") }
            print("PASS \(name)")
        }
    }
}
