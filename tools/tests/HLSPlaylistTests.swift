import Foundation

@main
struct HLSPlaylistTests {
    static func main() throws {
        let base = URL(string: "https://media.example/video/index.m3u8?token=one")!
        func parse(_ text: String) throws -> HLSPlaylist { try HLSPlaylist(text: text, url: base) }
        func rejects(_ text: String) {
            do { _ = try parse(text); fatalError("Accepted invalid playlist: \(text)") } catch {}
        }
        let media = try parse("#EXTM3U\n#EXTINF:5,\na.ts?token=a\n#EXTINF:6,\n../b.ts\n#EXT-X-ENDLIST\n")
        precondition(media.duration == 11 && media.resources.count == 2)
        precondition(media.resources[0].url.absoluteString == "https://media.example/video/a.ts?token=a")
        precondition(media.resources[1].url.absoluteString == "https://media.example/b.ts")
        precondition(!media.localText.contains("https:") && media.localText.contains("resource-1.media"))
        let master = try parse("#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"English, stereo\",DEFAULT=YES,URI=\"audio/index.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=1000,CODECS=\"avc1.64000d,mp4a.40.2\",AUDIO=\"a\"\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2000,AUDIO=\"a\"\nhigh/index.m3u8\n")
        precondition(master.variants.count == 2 && master.audio.count == 1 && master.audio[0].isDefault)
        precondition(master.variants[1].audioGroup == "a")
        let ranged = try parse("#EXTM3U\n#EXT-X-MAP:URI=\"all.mp4\",BYTERANGE=\"50@0\"\n#EXTINF:5,\n#EXT-X-BYTERANGE:100@50\nall.mp4\n#EXTINF:6,\n#EXT-X-BYTERANGE:110\nall.mp4\n#EXT-X-ENDLIST\n")
        precondition(ranged.resources.map { $0.rangeHeader! } == ["bytes=0-49", "bytes=50-149", "bytes=150-259"])
        precondition(!ranged.localText.contains("BYTERANGE"))
        let aes = try parse("#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:7\n#EXT-X-KEY:METHOD=AES-128,URI=\"key\",IV=0x01\n#EXTINF:11,\na.ts\n#EXT-X-ENDLIST\n")
        precondition(aes.resources[0].isKey && aes.localText.contains("IV=0x01"))
        precondition(aes.localText.contains("MEDIA-SEQUENCE:7"))
        rejects("<html>not a video</html>")
        rejects("#EXTM3U\n#EXTINF:11,\na.ts\n") // live
        rejects("#EXTM3U\n#EXTINF:nan,\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:11,\nfile:///private/data\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"key\"\n#EXTINF:11,\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,KEYFORMAT=\"com.apple.streamingkeydelivery\",URI=\"key\"\n#EXTINF:11,\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:11,\n#EXT-X-BYTERANGE:100\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:5,\n#EXT-X-BYTERANGE:100@0\na.ts\n#EXTINF:6,\n#EXT-X-BYTERANGE:100\nb.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:11,\n#EXT-X-BYTERANGE:100@9223372036854775807\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:11,\n#EXT-X-GAP\na.ts\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXTINF:11,\na.ts\n#EXT-X-ENDLIST\nmalicious.ts")
        rejects("#EXTM3U\n#EXTINF:11,\n#EXT-X-ENDLIST")
        rejects("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,BANDWIDTH=2\na.m3u8")
        print("HLS parser: relative URLs, variants/audio, ranges, AES-128 and 13 rejection cases passed")
    }
}
