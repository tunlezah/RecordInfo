import Foundation
import SwiftUI

@Observable
final class AppSettings {
    var audioBufferLength: Double = 20.0  // seconds (10-30)
    var detectionInterval: Double = 120.0  // seconds (30-300)
    var confidenceThreshold: Double = 0.6  // 0.0-1.0
    var cooldownDuration: Double = 30.0  // seconds
    var perTrackCooldown: Double = 300.0  // seconds
    var autoDetectionEnabled: Bool = true
    var gapDetectionEnabled: Bool = false
    var fallbackProviderEnabled: Bool = true
    var debugModeEnabled: Bool = false
    var acoustIDApiKey: String = ""
    var sampleRate: Double = 11025.0  // Hz
    var noiseGateThreshold: Float = 0.01
    var similarityThreshold: Double = 0.8  // for fingerprint comparison

    func save() {
        UserDefaults.standard.set(audioBufferLength, forKey: "audioBufferLength")
        UserDefaults.standard.set(detectionInterval, forKey: "detectionInterval")
        UserDefaults.standard.set(confidenceThreshold, forKey: "confidenceThreshold")
        UserDefaults.standard.set(cooldownDuration, forKey: "cooldownDuration")
        UserDefaults.standard.set(perTrackCooldown, forKey: "perTrackCooldown")
        UserDefaults.standard.set(autoDetectionEnabled, forKey: "autoDetectionEnabled")
        UserDefaults.standard.set(gapDetectionEnabled, forKey: "gapDetectionEnabled")
        UserDefaults.standard.set(fallbackProviderEnabled, forKey: "fallbackProviderEnabled")
        UserDefaults.standard.set(debugModeEnabled, forKey: "debugModeEnabled")
        UserDefaults.standard.set(acoustIDApiKey, forKey: "acoustIDApiKey")
        UserDefaults.standard.set(sampleRate, forKey: "sampleRate")
        UserDefaults.standard.set(noiseGateThreshold, forKey: "noiseGateThreshold")
        UserDefaults.standard.set(similarityThreshold, forKey: "similarityThreshold")
    }

    func load() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "audioBufferLength") != nil {
            audioBufferLength = defaults.double(forKey: "audioBufferLength")
        }
        if defaults.object(forKey: "detectionInterval") != nil {
            detectionInterval = defaults.double(forKey: "detectionInterval")
        }
        if defaults.object(forKey: "confidenceThreshold") != nil {
            confidenceThreshold = defaults.double(forKey: "confidenceThreshold")
        }
        if defaults.object(forKey: "cooldownDuration") != nil {
            cooldownDuration = defaults.double(forKey: "cooldownDuration")
        }
        if defaults.object(forKey: "perTrackCooldown") != nil {
            perTrackCooldown = defaults.double(forKey: "perTrackCooldown")
        }
        autoDetectionEnabled = defaults.object(forKey: "autoDetectionEnabled") != nil ? defaults.bool(forKey: "autoDetectionEnabled") : true
        gapDetectionEnabled = defaults.bool(forKey: "gapDetectionEnabled")
        fallbackProviderEnabled = defaults.object(forKey: "fallbackProviderEnabled") != nil ? defaults.bool(forKey: "fallbackProviderEnabled") : true
        debugModeEnabled = defaults.bool(forKey: "debugModeEnabled")
        if let key = defaults.string(forKey: "acoustIDApiKey") {
            acoustIDApiKey = key
        }
        if defaults.object(forKey: "sampleRate") != nil {
            sampleRate = defaults.double(forKey: "sampleRate")
        }
        if defaults.object(forKey: "noiseGateThreshold") != nil {
            noiseGateThreshold = defaults.float(forKey: "noiseGateThreshold")
        }
        if defaults.object(forKey: "similarityThreshold") != nil {
            similarityThreshold = defaults.double(forKey: "similarityThreshold")
        }
    }
}
