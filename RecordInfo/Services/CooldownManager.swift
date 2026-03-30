import Foundation

@Observable
@MainActor
final class CooldownManager: CooldownManagerProtocol {

    // MARK: - Configuration

    var globalCooldownDuration: TimeInterval = 30.0
    var perTrackCooldownDuration: TimeInterval = 300.0
    var similarityThreshold: Double = 0.8

    // MARK: - State

    private(set) var lastFingerprintHash: String?
    private(set) var lastGlobalDetectionDate: Date?
    private var perTrackCooldowns: [String: Date] = [:]

    // MARK: - Public API

    /// Determines whether detection should be skipped for the given fingerprint and track.
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool {
        if isInGlobalCooldown() {
            return true
        }

        // Skip if the fingerprint is identical to the last detected one and within per-track cooldown.
        if fingerprintHash == lastFingerprintHash, isTrackInCooldown(trackKey) {
            return true
        }

        if isTrackInCooldown(trackKey) {
            return true
        }

        return false
    }

    /// Registers a successful detection, starting cooldown timers.
    func registerDetection(fingerprintHash: String, trackKey: String) {
        let now = Date()
        lastFingerprintHash = fingerprintHash
        lastGlobalDetectionDate = now
        perTrackCooldowns[trackKey] = now
    }

    /// Whether the system is currently in global cooldown.
    func isInGlobalCooldown() -> Bool {
        guard let last = lastGlobalDetectionDate else { return false }
        return Date().timeIntervalSince(last) < globalCooldownDuration
    }

    /// Returns the remaining time (in seconds) of the global cooldown, or 0 if not in cooldown.
    func remainingCooldown() -> TimeInterval {
        guard let last = lastGlobalDetectionDate else { return 0 }
        let elapsed = Date().timeIntervalSince(last)
        return max(0, globalCooldownDuration - elapsed)
    }

    /// Resets all cooldown state.
    func reset() {
        lastFingerprintHash = nil
        lastGlobalDetectionDate = nil
        perTrackCooldowns.removeAll()
    }

    // MARK: - Track Key Helpers

    /// Generates a canonical track key from artist and title strings.
    static func trackKey(artist: String, title: String) -> String {
        "\(artist)_\(title)".lowercased()
    }

    // MARK: - Private

    private func isTrackInCooldown(_ key: String) -> Bool {
        guard let lastDetection = perTrackCooldowns[key] else { return false }
        return Date().timeIntervalSince(lastDetection) < perTrackCooldownDuration
    }
}
