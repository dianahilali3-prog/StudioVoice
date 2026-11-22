import AVFoundation
import Foundation
import Observation

/// In-app player (play/pause, skip, scrub) based on AVAudioPlayer.
@Observable
@MainActor
final class AudioPlayerController: NSObject, AVAudioPlayerDelegate {
    private(set) var url: URL?
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    var currentTime: TimeInterval = 0
    private(set) var waveform: [Float] = []

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    var progress: Double { duration > 0 ? currentTime / duration : 0 }
    var hasAudio: Bool { player != nil }

    func load(_ url: URL?) {
        stop()
        self.url = url
        player = nil
        waveform = []
        duration = 0
        currentTime = 0
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            duration = player.duration
        } catch {
            self.player = nil
        }
        Task.detached(priority: .utility) {
            let peaks = WaveformAnalyzer.peaks(of: url)
            await MainActor.run { [weak self] in
                if self?.url == url { self?.waveform = peaks }
            }
        }
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player else { return }
        AudioSessionManager.activatePlayback()
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: (player?.currentTime ?? 0) + seconds)
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
        currentTime = player.currentTime
    }

    func seek(toFraction fraction: Double) {
        seek(to: fraction * duration)
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = 0
            self.player?.currentTime = 0
        }
    }
}

enum AudioSessionManager {
    static func activatePlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }
}
