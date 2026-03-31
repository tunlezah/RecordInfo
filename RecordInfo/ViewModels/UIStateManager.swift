import Foundation
import SwiftUI
import AppKit

@MainActor
@Observable
final class UIStateManager {

    // MARK: - Services

    let audioService: AudioServiceProtocol
    let fingerprintService: FingerprintServiceProtocol
    let recognitionService: RecognitionServiceProtocol
    let cooldownManager: CooldownManagerProtocol
    let settings: AppSettings
    let trackHistory: TrackHistory

    // MARK: - State

    private(set) var appState: AppState = .idle
    private(set) var isListening: Bool = false
    private(set) var currentResult: IdentificationResult?
    private(set) var audioLevel: Float = 0.0
    private(set) var bufferFillPercentage: Double = 0.0

    // MARK: - Countdown Timers

    private(set) var secondsUntilNextDetection: TimeInterval = 0.0
    private(set) var cooldownRemaining: TimeInterval = 0.0

    // MARK: - Debug

    private(set) var debugLogEntries: [String] = []
    private(set) var lastAPIResponse: String = "No response yet"
    private(set) var lastDetectionTime: Date?

    // MARK: - Internal Tasks

    private var autoDetectionTask: Task<Void, Never>?
    private var cooldownTimerTask: Task<Void, Never>?
    private var audioLevelPollingTask: Task<Void, Never>?
    private var nowPlayingWindow: NSWindow?

    // MARK: - Initialization

    init(
        audioService: AudioServiceProtocol,
        fingerprintService: FingerprintServiceProtocol,
        recognitionService: RecognitionServiceProtocol,
        cooldownManager: CooldownManagerProtocol,
        settings: AppSettings = AppSettings(),
        trackHistory: TrackHistory = TrackHistory()
    ) {
        self.audioService = audioService
        self.fingerprintService = fingerprintService
        self.recognitionService = recognitionService
        self.cooldownManager = cooldownManager
        self.settings = settings
        self.trackHistory = trackHistory

        settings.load()
        log("UIStateManager initialized")
    }

    // MARK: - Public Methods

    func startListening() {
        guard !isListening else {
            log("Already listening, ignoring startListening call")
            return
        }

        log("Starting listening...")
        Task {
            do {
                try await audioService.start()
                isListening = true
                appState = .listening
                log("Audio service started successfully")
                startAudioLevelPolling()
                if settings.autoDetectionEnabled {
                    startAutoDetectionTimer()
                }
            } catch {
                let message = "Failed to start audio: \(error.localizedDescription)"
                appState = .error(message)
                log(message, isError: true)
            }
        }
    }

    func stopListening() {
        log("Stopping listening...")
        autoDetectionTask?.cancel()
        autoDetectionTask = nil
        cooldownTimerTask?.cancel()
        cooldownTimerTask = nil
        audioLevelPollingTask?.cancel()
        audioLevelPollingTask = nil
        audioService.stop()
        isListening = false
        audioLevel = 0.0
        bufferFillPercentage = 0.0
        secondsUntilNextDetection = 0.0
        cooldownRemaining = 0.0
        appState = .idle
        log("Listening stopped")
    }

    func manualIdentify() {
        guard isListening else {
            log("Cannot identify: not listening")
            return
        }
        if case .processing = appState {
            log("Already processing, ignoring manual identify")
            return
        }
        log("Manual identification triggered")
        Task { await performIdentification() }
    }

    // MARK: - Identification Pipeline

    func performIdentification() async {
        guard isListening else { return }
        appState = .processing

        do {
            let result = try await runIdentificationPipeline()
            await handleIdentificationSuccess(result)
        } catch is CancellationError {
            log("Identification cancelled")
            if isListening { appState = .listening }
        } catch {
            await handleIdentificationError(error)
        }
    }

    private func runIdentificationPipeline() async throws -> IdentificationResult? {
        let bufferData = audioService.getBufferData()
        guard !bufferData.isEmpty else {
            log("Audio buffer is empty, skipping")
            appState = .listening
            return nil
        }

        let fingerprint = try await fingerprintService.generateFingerprint(
            from: bufferData,
            sampleRate: Int(settings.sampleRate),
            duration: settings.audioBufferLength
        )
        let hash = fingerprintService.hashFingerprint(fingerprint)
        log("Fingerprint generated, hash: \(hash.prefix(16))...")

        if cooldownManager.isInGlobalCooldown() {
            let remaining = cooldownManager.remainingCooldown()
            log("Global cooldown active, \(Int(remaining))s remaining")
            appState = .coolingDown(remaining)
            startCooldownTimer()
            return nil
        }

        guard let result = try await recognitionService.identifyCurrentAudio() else {
            log("No match found")
            appState = .listening
            return nil
        }

        guard result.confidence >= settings.confidenceThreshold else {
            log("Below threshold: \(result.confidence) < \(settings.confidenceThreshold)")
            appState = .listening
            return nil
        }

        let trackKey = "\(result.artist)-\(result.trackTitle)"
        if cooldownManager.shouldSkip(fingerprintHash: hash, trackKey: trackKey) {
            log("Track '\(result.trackTitle)' skipped (cooldown)")
            appState = .listening
            return nil
        }

        cooldownManager.registerDetection(fingerprintHash: hash, trackKey: trackKey)
        return result
    }

    private func handleIdentificationSuccess(_ result: IdentificationResult?) async {
        guard let result else { return }
        currentResult = result
        lastDetectionTime = Date()
        trackHistory.add(result)
        appState = .identified(result)
        let pct = String(format: "%.1f%%", result.confidence * 100)
        log("Identified: \(result.trackTitle) by \(result.artist) (\(pct))")
        await transitionAfterIdentification()
    }

    private func transitionAfterIdentification() async {
        let duration = settings.cooldownDuration
        try? await Task.sleep(for: .seconds(3))
        guard isListening else { return }
        if duration > 0 {
            appState = .coolingDown(duration)
            startCooldownTimer()
        } else {
            appState = .listening
        }
    }

    private func handleIdentificationError(_ error: Error) async {
        let message = "Identification failed: \(error.localizedDescription)"
        log(message, isError: true)
        appState = .error(message)
        try? await Task.sleep(for: .seconds(3))
        if isListening { appState = .listening }
    }

    // MARK: - Auto Detection Timer

    func startAutoDetectionTimer() {
        autoDetectionTask?.cancel()
        let interval = settings.detectionInterval
        secondsUntilNextDetection = interval
        log("Auto-detection started: \(Int(interval))s interval")

        autoDetectionTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                var remaining = interval
                while remaining > 0, !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    remaining -= 1
                    self.secondsUntilNextDetection = remaining
                }
                guard !Task.isCancelled else { return }
                if case .listening = self.appState {
                    await self.performIdentification()
                }
                self.secondsUntilNextDetection = interval
            }
        }
    }

    // MARK: - Cooldown Timer

    private func startCooldownTimer() {
        cooldownTimerTask?.cancel()
        cooldownRemaining = cooldownManager.remainingCooldown()

        cooldownTimerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled else { return }
                let remaining = self.cooldownManager.remainingCooldown()
                self.cooldownRemaining = remaining
                if remaining <= 0 {
                    self.cooldownRemaining = 0
                    if self.isListening {
                        self.appState = .listening
                        self.log("Cooldown ended")
                    }
                    return
                }
                self.appState = .coolingDown(remaining)
            }
        }
    }

    // MARK: - Audio Level Polling

    private func startAudioLevelPolling() {
        audioLevelPollingTask?.cancel()
        audioLevelPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard !Task.isCancelled else { return }
                self.audioLevel = self.audioService.currentLevel
                self.bufferFillPercentage = self.audioService.bufferFillPercentage
            }
        }
    }

    // MARK: - Window Management

    func openNowPlayingWindow() {
        if let existing = nowPlayingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Now Playing"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.center()
        window.isReleasedWhenClosed = false

        let content = NowPlayingFullView()
            .environment(self)
            .environment(trackHistory)
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        nowPlayingWindow = window
    }

    // MARK: - Debug Logging

    func log(_ message: String, isError: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        debugLogEntries.append("[\(timestamp)] \(message)")
        if debugLogEntries.count > 500 {
            debugLogEntries.removeFirst(debugLogEntries.count - 500)
        }
        if isError {
            AppLogger.shared.error(message, category: .userInterface)
        } else {
            AppLogger.shared.log(message, category: .userInterface)
        }
    }
}

// MARK: - NowPlayingFullView

struct NowPlayingFullView: View {
    @Environment(UIStateManager.self) private var stateManager
    @Environment(TrackHistory.self) private var history

    var body: some View {
        NowPlayingView()
            .environment(stateManager)
            .environment(history)
    }
}
