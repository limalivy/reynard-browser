import Foundation

/// A finite HLS playlist. Only validated, local resource names reach the remuxer.
struct HLSPlaylist: Sendable {
    enum Failure: Error { case invalid, live, unsupportedEncryption, ambiguous, durationMismatch }
    struct Resource: Hashable, Sendable {
        let url: URL
        let offset: Int64?
        let length: Int64?
        let isKey: Bool
        var rangeHeader: String? {
            guard let offset, let length else { return nil }
            return "bytes=\(offset)-\(offset + length - 1)"
        }
    }
    struct Variant: Sendable {
        let url: URL
        let bandwidth: Int64
        let audioGroup: String?
    }
    struct Audio: Sendable {
        let url: URL
        let group: String
        let isDefault: Bool
    }
    let variants: [Variant]
    let audio: [Audio]
    let resources: [Resource]
    let localText: String
    let duration: Double

    init(text: String, url: URL) throws {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first == "#EXTM3U" else { throw Failure.invalid }
        var variants: [Variant] = [], audio: [Audio] = [], resources: [Resource] = []
        var output = ["#EXTM3U"], duration = 0.0, segmentCount = 0
        var stream: [String: String]?, segmentDuration: Double?, byteRange: String?
        var previousRange: (url: URL, end: Int64)?
        var ended = false

        func resolve(_ value: String?) throws -> URL {
            guard let value, let resolved = URL(string: value, relativeTo: url)?.absoluteURL,
                  ["http", "https"].contains(resolved.scheme?.lowercased() ?? ""),
                  resolved.host != nil else { throw Failure.invalid }
            return resolved
        }
        func addResource(_ value: String?, range: String? = nil, key: Bool = false, segment: Bool = true) throws -> String {
            let resolved = try resolve(value)
            var offset: Int64?, length: Int64?
            if let range {
                let parts = range.split(separator: "@", omittingEmptySubsequences: false)
                guard (1...2).contains(parts.count), let size = Int64(parts[0]), size > 0 else { throw Failure.invalid }
                let start = parts.count == 2 ? Int64(parts[1]) : (segment && previousRange?.url == resolved ? previousRange?.end : nil)
                guard let start, start >= 0, size <= Int64.max - start else { throw Failure.invalid }
                offset = start; length = size
                if segment { previousRange = (resolved, start + size) }
            } else if segment { previousRange = nil }
            let resource = Resource(url: resolved, offset: offset, length: length, isKey: key)
            let index: Int
            if let existing = resources.firstIndex(of: resource) { index = existing }
            else { index = resources.count; resources.append(resource) }
            return "resource-\(index).\(key ? "key" : "media")"
        }

        for line in lines.dropFirst() where !line.isEmpty {
            guard !ended else { throw Failure.invalid }
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                guard stream == nil else { throw Failure.invalid }
                stream = try Self.attributes(String(line.dropFirst(18)))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attrs = try Self.attributes(String(line.dropFirst(13)))
                if attrs["TYPE"] == "AUDIO", let uri = attrs["URI"], let group = attrs["GROUP-ID"] {
                    audio.append(Audio(url: try resolve(uri), group: group, isDefault: attrs["DEFAULT"] == "YES"))
                }
            } else if line.hasPrefix("#EXTINF:") {
                guard segmentDuration == nil,
                      let value = Double(line.dropFirst(8).split(separator: ",", omittingEmptySubsequences: false)[0]),
                      value.isFinite, value > 0 else { throw Failure.invalid }
                segmentDuration = value
                output.append("#EXTINF:\(value),")
            } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                guard byteRange == nil else { throw Failure.invalid }
                byteRange = String(line.dropFirst(17))
            } else if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = try Self.attributes(String(line.dropFirst(11)))
                let name = try addResource(attrs["URI"], range: attrs["BYTERANGE"], segment: false)
                output.append("#EXT-X-MAP:URI=\"\(name)\"")
            } else if line.hasPrefix("#EXT-X-KEY:") {
                let attrs = try Self.attributes(String(line.dropFirst(11)))
                if attrs["METHOD"] == "NONE" { output.append("#EXT-X-KEY:METHOD=NONE"); continue }
                guard attrs["METHOD"] == "AES-128", attrs["KEYFORMAT"] == nil || attrs["KEYFORMAT"] == "identity" else {
                    throw Failure.unsupportedEncryption
                }
                let name = try addResource(attrs["URI"], key: true, segment: false)
                var keyLine = "#EXT-X-KEY:METHOD=AES-128,URI=\"\(name)\""
                if let iv = attrs["IV"] {
                    guard iv.range(of: "^0x[0-9a-fA-F]{1,32}$", options: .regularExpression) != nil else { throw Failure.invalid }
                    keyLine += ",IV=\(iv)"
                }
                output.append(keyLine)
            } else if line == "#EXT-X-ENDLIST" {
                ended = true; output.append(line)
            } else if line == "#EXT-X-GAP" { throw Failure.invalid
            } else if line == "#EXT-X-DISCONTINUITY" || line == "#EXT-X-INDEPENDENT-SEGMENTS" {
                output.append(line)
            } else if ["#EXT-X-VERSION:", "#EXT-X-TARGETDURATION:", "#EXT-X-MEDIA-SEQUENCE:", "#EXT-X-DISCONTINUITY-SEQUENCE:"].contains(where: line.hasPrefix) {
                guard let value = line.split(separator: ":").last, UInt64(value) != nil else { throw Failure.invalid }
                output.append(line)
            } else if !line.hasPrefix("#") {
                if let attrs = stream {
                    guard let bandwidth = Int64(attrs["BANDWIDTH"] ?? ""), bandwidth > 0 else { throw Failure.invalid }
                    variants.append(Variant(url: try resolve(line), bandwidth: bandwidth, audioGroup: attrs["AUDIO"]))
                    stream = nil
                } else {
                    guard let value = segmentDuration else { throw Failure.invalid }
                    duration += value; segmentCount += 1
                    output.append(try addResource(line, range: byteRange))
                    byteRange = nil; segmentDuration = nil
                }
            }
        }
        guard stream == nil, segmentDuration == nil, byteRange == nil,
              duration.isFinite, resources.count <= 100_000 else { throw Failure.invalid }
        if variants.isEmpty {
            guard ended else { throw Failure.live }
            guard segmentCount > 0 else { throw Failure.invalid }
        } else if segmentCount > 0 { throw Failure.invalid }
        self.variants = variants; self.audio = audio; self.resources = resources
        self.duration = duration; self.localText = output.joined(separator: "\n") + "\n"
    }

    private static func attributes(_ text: String) throws -> [String: String] {
        let expression = try NSRegularExpression(pattern: "(?:^|,)([A-Z0-9-]+)=(\"[^\"]*\"|[^,]+)")
        let input = text as NSString
        var result: [String: String] = [:], consumed = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: input.length)) {
            guard match.range.location == consumed else { throw Failure.invalid }
            consumed = NSMaxRange(match.range)
            let key = input.substring(with: match.range(at: 1))
            var value = input.substring(with: match.range(at: 2))
            if value.hasPrefix("\"") { value = String(value.dropFirst().dropLast()) }
            guard result[key] == nil else { throw Failure.invalid }
            result[key] = value
        }
        guard consumed == input.length else { throw Failure.invalid }
        return result
    }
}
