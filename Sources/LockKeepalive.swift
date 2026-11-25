import AVFoundation
import os

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
    /// either one without the other is a toggle that does nothing or a mode nothing uses
    /// (Tests/App/AppTests.swift fails on the mismatch).
    static let isAvailable = false

    private static var player: AVAudioPlayer?
    private static var wanted = false
    private static var observing = false
    private static let log = Logger(subsystem: "dev.bence.stagetimer", category: "keepalive")

    /// Whether the silence should be playing. Safe, and useful, to call again with the same
    /// answer: if it should be playing and is not, this starts it again. `TimerModel` does so
    /// whenever a scene becomes active, which is the one chance to recover from an interruption
    /// that ended while the app was suspended and so was never reported.
    static func set(wanted: Bool) {
        self.wanted = wanted && isAvailable
        if self.wanted {
            observe()
            start()
        } else {
            stop()
        }
    }

    private static func start() {
        if let player, player.isPlaying { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try self.player ?? AVAudioPlayer(data: silence, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0
            if player.play() {
                self.player = player
            } else {
                // Dropped rather than kept, so the next attempt builds a new one.
                self.player = nil
                log.error("Lock keepalive: the player refused to play")
            }
        } catch {
            player = nil
            log.error("Lock keepalive could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func stop() {
        guard let player else { return }
        player.stop()
        self.player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A phone call, an alarm or Siri interrupts even a session that mixes with others, and the
    /// system pauses the player without resuming it afterwards. Left alone, the keepalive would
    /// be silently gone and the display would freeze at the next press of the top button.
    private static func observe() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        _ = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard type == AVAudioSession.InterruptionType.ended.rawValue, LockKeepalive.wanted else { return }
                LockKeepalive.start()
            }
        }
        // After the media server restarts, existing players are dead objects.
        _ = center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                LockKeepalive.player = nil
                if LockKeepalive.wanted { LockKeepalive.start() }
            }
        }
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
