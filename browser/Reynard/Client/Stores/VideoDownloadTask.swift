import Foundation
import GeckoView

@MainActor
final class VideoDownloadTask {
    private struct Selection {
        let url: URL
        let playlist: HLSPlaylist?
        let directFile: URL?
        var audio: HLSPlaylist?
        var audioURLs: Set<URL> = []
    }
    private let session: GeckoSession
    private let context: VideoDownloadContext
    private let sources: [URL]
    private let expectedDuration: Double
    private let isFallback: Bool
    private let jobId = UUID().uuidString
    private var task: Task<Void, Never>?
    private var bytes: Int64 = 0
    private var progress: ((Int64) -> Void)?
    private var cache: [URL: VideoResource] = [:]

    init(session: GeckoSession, context: VideoDownloadContext, sources: [URL], duration: Double, isFallback: Bool) {
        self.session = session; self.context = context; self.sources = sources
        self.expectedDuration = duration; self.isFallback = isFallback
    }

    func cancel() {
        task?.cancel()
        session.finishVideoDownload(jobId: jobId)
    }

    func start(output: URL, progress: @escaping (Int64) -> Void, completion: @escaping (Bool) -> Void) {
        self.progress = progress
        task = Task {
            defer {
                session.finishVideoDownload(jobId: jobId)
                try? FileManager.default.removeItem(at: output.deletingLastPathComponent())
                task = nil
            }
            do {
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                var selections: [URL: Selection] = [:]
                for source in sources {
                    try Task.checkCancellation()
                    do {
                        let selection = try await resolve(source)
                        if let playlist = selection.playlist {
                            guard playlist.duration > 10,
                                  abs(playlist.duration - expectedDuration) <= max(0.5, expectedDuration * 0.01) else {
                                throw HLSPlaylist.Failure.durationMismatch
                            }
                        } else if isFallback { throw HLSPlaylist.Failure.invalid }
                        if selections[selection.url] == nil || selection.audio != nil { selections[selection.url] = selection }
                    } catch {
                        if !isFallback || Task.isCancelled { throw error }
                    }
                }
                let audioURLs = Set(selections.values.flatMap { $0.audioURLs })
                selections = selections.filter { !audioURLs.contains($0.key) }
                guard selections.count == 1, let selection = selections.values.first else { throw HLSPlaylist.Failure.ambiguous }
                if let direct = selection.directFile {
                    try await validateDuration(direct)
                    try Task.checkCancellation()
                    try FileManager.default.copyItem(at: direct, to: output)
                } else if let playlist = selection.playlist {
                    let directory = output.deletingLastPathComponent()
                    let video = try await save(playlist, to: directory.appendingPathComponent("video"))
                    var input = video
                    if let audio = selection.audio {
                        guard abs(audio.duration - playlist.duration) <= max(1, playlist.duration * 0.01) else {
                            throw HLSPlaylist.Failure.durationMismatch
                        }
                        _ = try await save(audio, to: directory.appendingPathComponent("audio"))
                        input = directory.appendingPathComponent("index.m3u8")
                        try "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"Audio\",DEFAULT=YES,URI=\"audio/index.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO=\"audio\"\nvideo/index.m3u8\n".write(to: input, atomically: true, encoding: .utf8)
                    }
                    let status = await Self.remux(input, to: output)
                    guard status >= 0 else { throw HLSPlaylist.Failure.invalid }
                    try await validateDuration(output)
                    try Task.checkCancellation()
                }
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    private func fetch(_ url: URL, range: String? = nil, maxBytes: Int64 = 0) async throws -> VideoResource {
        try Task.checkCancellation()
        let resource = try await session.fetchVideoResource(url: url, jobId: jobId, context: context, range: range, maxBytes: maxBytes)
        try Task.checkCancellation()
        bytes += resource.bytes; progress?(bytes)
        return resource
    }

    private func resolve(_ url: URL, depth: Int = 0) async throws -> Selection {
        guard depth < 5 else { throw HLSPlaylist.Failure.invalid }
        let resource: VideoResource
        if let cached = cache[url] { resource = cached }
        else {
            resource = try await fetch(url, maxBytes: isFallback || depth > 0 || url.pathExtension.lowercased() == "m3u8" ? 2_097_152 : 0)
            cache[url] = resource
        }
        let file = try FileHandle(forReadingFrom: resource.fileURL)
        defer { try? file.close() }
        let prefix = file.readData(ofLength: 2_097_153)
        guard prefix.starts(with: Data("#EXTM3U".utf8)) else {
            return Selection(url: resource.responseURL, playlist: nil, directFile: resource.fileURL)
        }
        guard prefix.count <= 2_097_152, let text = String(data: prefix, encoding: .utf8) else { throw HLSPlaylist.Failure.invalid }
        let playlist = try HLSPlaylist(text: text, url: resource.responseURL)
        guard let variant = playlist.variants.max(by: { $0.bandwidth < $1.bandwidth }) else {
            return Selection(url: resource.responseURL, playlist: playlist, directFile: nil)
        }
        var selected = try await resolve(variant.url, depth: depth + 1)
        guard selected.playlist != nil else { throw HLSPlaylist.Failure.invalid }
        let renditions = playlist.audio.filter { $0.group == variant.audioGroup }
        if let audio = renditions.first(where: { $0.isDefault }) ?? renditions.first {
            let resolved = try await resolve(audio.url, depth: depth + 1)
            guard let audioPlaylist = resolved.playlist else { throw HLSPlaylist.Failure.invalid }
            selected.audio = audioPlaylist
            selected.audioURLs.insert(resolved.url)
        }
        return selected
    }

    private func save(_ playlist: HLSPlaylist, to directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, resource) in playlist.resources.enumerated() {
            let result = try await fetch(resource.url, range: resource.rangeHeader, maxBytes: resource.isKey ? 16 : 1_073_741_824)
            if let length = resource.length, result.bytes != length { throw HLSPlaylist.Failure.invalid }
            if resource.isKey && result.bytes != 16 { throw HLSPlaylist.Failure.invalid }
            let name = "resource-\(index).\(resource.isKey ? "key" : "media")"
            try FileManager.default.moveItem(at: result.fileURL, to: directory.appendingPathComponent(name))
        }
        let local = directory.appendingPathComponent("index.m3u8")
        try playlist.localText.write(to: local, atomically: true, encoding: .utf8)
        return local
    }

    private func validateDuration(_ file: URL) async throws {
        let duration: Double = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ReynardVideoDuration(file.path))
            }
        }
        guard duration.isFinite, duration > 10,
              abs(duration - expectedDuration) <= max(0.5, expectedDuration * 0.01) else {
            throw HLSPlaylist.Failure.durationMismatch
        }
    }

    private static func remux(_ input: URL, to output: URL) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ReynardRemuxVideo(input.path, output.path))
            }
        }
    }
}
