import AVFoundation
import UIKit

/// Keeps the app alive after the operator presses the top button so a connected display keeps
/// counting. Locking the device backgrounds the app, iOS suspends it within seconds, and the
/// external display then freezes on the last frame it drew. An active audio session is what lets
/// an app keep running in the background (`UIBackgroundModes: audio`), so while the setting is on
/// and a display is connected this plays looped silence, mixed with other audio so nothing the
/// venue is playing is interrupted or ducked.
@MainActor
enum LockKeepalive {
    private static var player: AVAudioPlayer?

    static func update(enabled: Bool, displayConnected: Bool) {
        if enabled && displayConnected { start() } else { stop() }
    }

    private static func start() {
        guard player == nil else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: silence, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    private static func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// One second of 16-bit mono silence at 8 kHz as a WAV file, built in code so the app ships
    /// no audio asset.
    private static let silence: Data = {
        let sampleRate: UInt32 = 8000
        let dataSize = sampleRate * 2
        var data = Data()
        func append(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append(_ tag: String) { data.append(contentsOf: Array(tag.utf8)) }
        append("RIFF"); append(UInt32(36 + dataSize)); append("WAVE")
        append("fmt "); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        append("data"); append(dataSize); data.append(Data(count: Int(dataSize)))
        return data
    }()
}
