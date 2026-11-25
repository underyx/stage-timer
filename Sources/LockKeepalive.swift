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
    /// Held back from 1.1: the owner wants the first update through App Review without the
    /// question a background audio mode invites (2026-11-25). While this is false the toggle is
    /// hidden, nothing plays, and project.yml declares no `UIBackgroundModes`. To ship the option,
    /// set this to true and restore `UIBackgroundModes: [audio]` in project.yml in the same change;
    /// either one without the other is a toggle that does nothing or a mode nothing uses.
    static let isAvailable = false

    private static var player: AVAudioPlayer?

    static func update(enabled: Bool, displayConnected: Bool) {
        if isAvailable && enabled && displayConnected { start() } else { stop() }
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
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func tag(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        tag("RIFF"); u32(36 + dataSize); tag("WAVE")
        tag("fmt "); u32(16); u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        tag("data"); u32(dataSize); data.append(Data(count: Int(dataSize)))
        return data
    }()
}
