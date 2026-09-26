import Foundation

public struct VideoDownloadContext {
    let innerWindowId: Int64
    let referrerInfo: String
    let userAgent: String

    init?(payload: [String: Any]?) {
        guard let innerWindowId = PayloadValue.int64(payload?["innerWindowId"]),
              let referrerInfo = payload?["referrerInfo"] as? String,
              let userAgent = payload?["userAgent"] as? String else { return nil }
        self.innerWindowId = innerWindowId
        self.referrerInfo = referrerInfo
        self.userAgent = userAgent
    }
}

public struct VideoResource {
    public let fileURL: URL
    public let responseURL: URL
    public let contentType: String?
    public let bytes: Int64
}

extension GeckoSession {
    @MainActor
    public func fetchVideoResource(url: URL, jobId: String, context: VideoDownloadContext,
                                   range: String? = nil, maxBytes: Int64 = 0) async throws -> VideoResource {
        let response = try await dispatcher.query(type: "GeckoView:FetchVideoResource", message: [
            "url": url.absoluteString, "jobId": jobId, "range": range, "maxBytes": maxBytes,
            "context": ["innerWindowId": context.innerWindowId, "referrerInfo": context.referrerInfo,
                        "userAgent": context.userAgent],
        ])
        guard let payload = response as? [String: Any],
              let path = payload["path"] as? String,
              let uri = payload["url"] as? String, let responseURL = URL(string: uri),
              let bytes = PayloadValue.int64(payload["bytes"]) else {
            throw GeckoHandlerError("Invalid video response")
        }
        return VideoResource(fileURL: URL(fileURLWithPath: path), responseURL: responseURL,
                             contentType: payload["contentType"] as? String, bytes: bytes)
    }

    @MainActor
    public func finishVideoDownload(jobId: String) {
        dispatcher.dispatch(type: "GeckoView:FinishVideoDownload", message: ["jobId": jobId])
    }
}
