import Foundation
import SwiftUI
import AppKit

// MARK: - Service Protocols

@MainActor
protocol AudioServiceProtocol: AnyObject, Sendable {
    func start() async throws
    func stop()
    func getBufferData() -> Data
    var currentLevel: Float { get }
    var bufferFillPercentage: Double { get }
    var isRunning: Bool { get }
}

@MainActor
protocol FingerprintServiceProtocol: Sendable {
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String
    func hashFingerprint(_ fingerprint: String) -> String
}

@MainActor
protocol RecognitionServiceProtocol: Sendable {
    func identifyCurrentAudio() async throws -> IdentificationResult?
}

@MainActor
protocol CooldownManagerProtocol: Sendable {
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool
    func registerDetection(fingerprintHash: String, trackKey: String)
    func isInGlobalCooldown() -> Bool
    func remainingCooldown() -> TimeInterval
}

// MARK: - UIStateManager

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
                let message = "Failed to start audio service: \(error.localizedDescription)"
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
        Task {
            await performIdentification()
        }
    }

    // MARK: - Identification

    func performIdentification() async {
        guard isListening else {
            log("Cannot perform identification: not listening")
            return
        }

        appState = .processing
        log("Starting identification...")

        do {
            let bufferData = audioService.getBufferData()

            guard !bufferData.isEmpty else {
                log("Audio buffer is empty, skipping identification")
                appState = .listening
                return
            }

            let fingerprint = try await fingerprintService.generateFingerprint(
                from: bufferData,
                sampleRate: Int(settings.sampleRate),
                duration: settings.audioBufferLength
            )
            let fingerprintHash = fingerprintService.hashFingerprint(fingerprint)
            log("Fingerprint generated, hash: \(fingerprintHash.prefix(16))...")

            // Check cooldown before making network request
            if cooldownManager.isInGlobalCooldown() {
                let remaining = cooldownManager.remainingCooldown()
                log("Global cooldown active, \(Int(remaining))s remaining")
                appState = .coolingDown(remaining)
                startCooldownTimer()
                return
            }

            guard let result = try await recognitionService.identifyCurrentAudio() else {
                log("No match found")
                appState = .listening
                return
            }

            // Check confidence threshold
            guard result.confidence >= settings.confidenceThreshold else {
                log("Result below confidence threshold: \(result.confidence) < \(settings.confidenceThreshold)")
                appState = .listening
                return
            }

            let trackKey = "\(result.artist)-\(result.trackTitle)"

            // Check per-track cooldown
            if cooldownManager.shouldSkip(fingerprintHash: fingerprintHash, trackKey: trackKey) {
                log("Track '\(result.trackTitle)' skipped due to cooldown")
                appState = .listening
                return
            }

            // Success - register and update state
            cooldownManager.registerDetection(fingerprintHash: fingerprintHash, trackKey: trackKey)
            currentResult = result
            lastDetectionTime = Date()
            trackHistory.add(result)
            appState = .identified(result)
            log("Identified: \(result.trackTitle) by \(result.artist) (confidence: \(String(format: "%.1f%%", result.confidence * 100)))")

            // Transition to cooldown after identification
            let cooldownDuration = settings.cooldownDuration
            if cooldownDuration > 0 {
                try? await Task.sleep(for: .seconds(3))
                guard isListening else { return }
                appState = .coolingDown(cooldownDuration)
                startCooldownTimer()
            } else {
                try? await Task.sleep(for: .seconds(3))
                guard isListening else { return }
                appState = .listening
            }

        } catch is CancellationError {
            log("Identification cancelled")
            if isListening {
                appState = .listening
            }
        } catch {
            let message = "Identification failed: \(error.localizedDescription)"
            log(message, isError: true)
            appState = .error(message)

            // Recover back to listening after a delay
            try? await Task.sleep(for: .seconds(3))
            if isListening {
                appState = .listening
            }
        }
    }

    // MARK: - Auto Detection Timer

    func startAutoDetectionTimer() {
        autoDetectionTask?.cancel()

        let interval = settings.detectionInterval
        secondsUntilNextDetection = interval
        log("Auto-detection timer started with interval: \(Int(interval))s")

        autoDetectionTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                // Count down every second
                var remaining = interval
                while remaining > 0, !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                    remaining -= 1
                    await MainActor.run {
                        self.secondsUntilNextDetection = remaining
                    }
                }

                guard !Task.isCancelled else { return }

                // Only trigger if we're in a listening state (not processing, cooling down, etc.)
                let currentState = await MainActor.run { self.appState }
                if case .listening = currentState {
                    await self.performIdentification()
                } else {
                    await MainActor.run {
                        self.log("Auto-detection skipped, current state: \(currentState.displayText)")
                    }
                }

                // Reset countdown for next cycle
                await MainActor.run {
                    self.secondsUntilNextDetection = interval
                }
            }
        }
    }

    // MARK: - Cooldown Timer

    private func startCooldownTimer() {
        cooldownTimerTask?.cancel()

        cooldownRemaining = cooldownManager.remainingCooldown()
        log("Cooldown timer started: \(Int(cooldownRemaining))s")

        cooldownTimerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                let remaining = self.cooldownManager.remainingCooldown()
                await MainActor.run {
                    self.cooldownRemaining = remaining

                    if remaining <= 0 {
                        self.cooldownRemaining = 0
                        if self.isListening {
                            self.appState = .listening
                            self.log("Cooldown ended, resuming listening")
                        }
                    } else {
                        self.appState = .coolingDown(remaining)
                    }
                }

                if remaining <= 0 {
                    return
                }
            }
        }
    }

    // MARK: - Audio Level Polling

    private func startAudioLevelPolling() {
        audioLevelPollingTask?.cancel()

        audioLevelPollingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                let level = self.audioService.currentLevel
                let fill = self.audioService.bufferFillPercentage

                await MainActor.run {
                    self.audioLevel = level
                    self.bufferFillPercentage = fill
                }
            }
        }
    }

    // MARK: - Window Management

    func openNowPlayingWindow() {
        if let existingWindow = nowPlayingWindow {
            existingWindow.makeKeyAndOrderFront(nil)
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

        let nowPlayingContentView = NowPlayingFullView()
            .environment(self)
            .environment(trackHistory)
        let hostingView = NSHostingView(rootView: nowPlayingContentView)
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        nowPlayingWindow = window
        log("Now Playing window opened")
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
        log("Settings window opened")
    }

    // MARK: - Debug Logging

    private func log(_ message: String, isError: Bool = false) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        debugLogEntries.append(entry)

        // Keep a reasonable number of entries
        if debugLogEntries.count > 500 {
            debugLogEntries.removeFirst(debugLogEntries.count - 500)
        }

        if isError {
            AppLogger.shared.error(message, category: .ui)
        } else {
            AppLogger.shared.log(message, category: .ui)
        }
    }
}

// MARK: - NowPlayingFullView (wrapper for window)

struct NowPlayingFullView: View {
    @Environment(UIStateManager.self) private var stateManager
    @Environment(TrackHistory.self) private var history

    var body: some View {
        NowPlayingView()
            .environment(stateManager)
            .environment(history)
    }
}
