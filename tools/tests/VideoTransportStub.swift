// Deterministic transport for exercising the production download pipeline.
// Gecko's real cookies, redirects and IPC require separate app UI tests.
import Foundation

public struct VideoDownloadContext { public init() {} }
public struct VideoResource {
    public let fileURL: URL
    public let responseURL: URL
    public let contentType: String?
    public let bytes: Int64
}
@MainActor
public final class GeckoSession {
    private let root: URL
    private let temporary: URL
    public init(root: URL, temporary: URL) { self.root = root; self.temporary = temporary }
    public func fetchVideoResource(url: URL, jobId: String, context: VideoDownloadContext,
                                   range: String?, maxBytes: Int64) async throws -> VideoResource {
        let source = root.appendingPathComponent(url.scheme == "blob" ? "video-11s.mp4" : url.path)
        var data = try Data(contentsOf: source)
        if let range {
            let parts = range.dropFirst(6).split(separator: "-").map { Int($0)! }
            data = data.subdata(in: parts[0]..<(parts[1] + 1))
        }
        if maxBytes > 0 && data.count > maxBytes { throw URLError(.dataLengthExceedsMaximum) }
        let directory = temporary.appendingPathComponent(jobId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString)
        try data.write(to: file)
        return VideoResource(fileURL: file, responseURL: url, contentType: nil, bytes: Int64(data.count))
    }
    public func finishVideoDownload(jobId: String) {
        try? FileManager.default.removeItem(at: temporary.appendingPathComponent(jobId))
    }
}
