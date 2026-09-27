import Foundation

/// Local file positions only; no page URLs or authentication data are stored.
final class VideoPlaybackProgressStore {
    private let defaults: UserDefaults
    private let storageKey = "VideoPlayer.positions.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func key(for url: URL) -> String? {
        var file = url
        file.removeAllCachedResourceValues()
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modified = values.contentModificationDate else { return nil }
        // Download names are unique within Downloads; the container UUID can change on an app update.
        return "\(url.lastPathComponent)|\(size)|\(modified.timeIntervalSince1970)"
    }

    func position(for url: URL, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, let key = key(for: url),
              let records = defaults.dictionary(forKey: storageKey) as? [String: [String: Double]],
              let position = records[key]?["position"], position.isFinite,
              position >= 3, duration - position > 3 else { return nil }
        return position
    }

    func save(_ position: Double, duration: Double, for url: URL) {
        guard position.isFinite, duration.isFinite, duration > 0, let key = key(for: url) else { return }
        var records = defaults.dictionary(forKey: storageKey) as? [String: [String: Double]] ?? [:]
        if position < 3 || duration - position <= 3 {
            records.removeValue(forKey: key)
        } else {
            records[key] = ["position": position, "updated": Date().timeIntervalSince1970]
        }
        if records.count > 200 {
            let oldest = records.sorted { ($0.value["updated"] ?? 0) < ($1.value["updated"] ?? 0) }
            for record in oldest.prefix(records.count - 200) { records.removeValue(forKey: record.key) }
        }
        defaults.set(records, forKey: storageKey)
    }

    func remove(_ url: URL) {
        guard let key = key(for: url) else { return }
        var records = defaults.dictionary(forKey: storageKey) as? [String: [String: Double]] ?? [:]
        records.removeValue(forKey: key)
        defaults.set(records, forKey: storageKey)
    }
}
