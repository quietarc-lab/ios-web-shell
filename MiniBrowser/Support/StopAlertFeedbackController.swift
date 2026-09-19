import AVFAudio
import Combine
import Foundation
import UIKit

/// Repeats a short in-app tone and an error haptic while a moderation stop
/// alert is waiting for confirmation. It deliberately does not configure an
/// audio session, request notification permissions, or attempt to bypass the
/// silent/focus modes.
@MainActor
final class StopAlertFeedbackController: ObservableObject {
    static let interval: TimeInterval = 2

    private(set) var isActive = false
    private(set) var pulseCount = 0
    private var timer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private let haptic = UINotificationFeedbackGenerator()

    func startIfNeeded() {
        guard !isActive else { return }
        isActive = true
        pulseCount = 0
        if let tone = Self.makeToneWAV() {
            audioPlayer = try? AVAudioPlayer(data: tone)
            audioPlayer?.prepareToPlay()
        }
        pulse()
        let timer = Timer(timeInterval: Self.interval,
                          repeats: true) { [weak self] _ in
            self?.pulse()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        guard isActive || timer != nil || audioPlayer != nil else { return }
        timer?.invalidate()
        timer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isActive = false
    }

    private func pulse() {
        guard isActive else { return }
        pulseCount += 1
        haptic.prepare()
        haptic.notificationOccurred(.error)
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        audioPlayer?.play()
    }

    /// Creates a tiny PCM tone in memory so the alert does not depend on a
    /// user file or a separately managed audio asset.
    private static func makeToneWAV() -> Data? {
        let sampleRate: UInt32 = 44_100
        let duration = 0.14
        let frameCount = Int(Double(sampleRate) * duration)
        guard frameCount > 0 else { return nil }

        var pcm = Data(capacity: frameCount * 2)
        for frame in 0..<frameCount {
            let position = Double(frame) / Double(sampleRate)
            let fadeIn = min(1, position * 45)
            let fadeOut = min(1, (duration - position) * 45)
            let amplitude = 0.24 * max(0, min(fadeIn, fadeOut))
            let sample = Int16(sin(position * 2 * .pi * 880) * amplitude * 32_767)
            var littleEndianSample = sample.littleEndian
            withUnsafeBytes(of: &littleEndianSample) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        var wav = Data()
        wav.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(UInt32(36 + pcm.count), to: &wav)
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(16, to: &wav)
        appendUInt16(1, to: &wav) // PCM
        appendUInt16(1, to: &wav) // mono
        appendUInt32(sampleRate, to: &wav)
        appendUInt32(sampleRate * 2, to: &wav)
        appendUInt16(2, to: &wav)
        appendUInt16(16, to: &wav)
        wav.append(contentsOf: Array("data".utf8))
        appendUInt32(UInt32(pcm.count), to: &wav)
        wav.append(contentsOf: pcm)
        return wav
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
