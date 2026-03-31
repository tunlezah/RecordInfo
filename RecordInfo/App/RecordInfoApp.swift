import SwiftUI

@main
struct RecordInfoApp: App {
    @State private var stateManager: UIStateManager
    @State private var settings: AppSettings
    @State private var trackHistory: TrackHistory

    init() {
        let appSettings = AppSettings()
        appSettings.load()

        let history = TrackHistory()

        let audioService = AudioService()
        audioService.bufferLengthSeconds = appSettings.audioBufferLength
        audioService.sampleRate = appSettings.sampleRate
        audioService.noiseGateThreshold = appSettings.noiseGateThreshold

        let fingerprintService = FingerprintService()

        let cooldownManager = CooldownManager()
        cooldownManager.globalCooldownDuration = appSettings.cooldownDuration
        cooldownManager.perTrackCooldownDuration = appSettings.perTrackCooldown
        cooldownManager.similarityThreshold = appSettings.similarityThreshold

        let acoustIDProvider = AcoustIDProvider(
            apiKey: appSettings.acoustIDApiKey,
            fingerprintService: fingerprintService
        )
        let fallbackProvider = StubFallbackProvider()

        let recognitionService = RecognitionService(
            audioService: audioService,
            fingerprintService: fingerprintService,
            cooldownManager: cooldownManager,
            primaryProvider: acoustIDProvider,
            fallbackProvider: fallbackProvider,
            settings: appSettings
        )

        let manager = UIStateManager(
            audioService: audioService,
            fingerprintService: fingerprintService,
            recognitionService: recognitionService,
            cooldownManager: cooldownManager,
            settings: appSettings,
            trackHistory: history
        )

        _stateManager = State(initialValue: manager)
        _settings = State(initialValue: appSettings)
        _trackHistory = State(initialValue: history)
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(stateManager)
                .environment(settings)
                .environment(trackHistory)
        }
        .windowResizability(.contentSize)
        .defaultSize(
            width: Constants.UserInterface.mainWindowWidth,
            height: Constants.UserInterface.mainWindowHeight
        )
    }
}
