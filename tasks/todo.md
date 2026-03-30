# RecordInfo - macOS Music Recognition App

## Implementation Plan

### Phase 1: Project Scaffolding
- [ ] Create Xcode project structure (Swift Package-style with directories)
- [ ] Create `.gitignore`, `LICENSE`, `README.md`
- [ ] Set up the Swift Package / Xcode project files
- [ ] Create modular directory structure: Services/, Models/, Views/, Utilities/

### Phase 2: Core Models & Protocols
- [ ] Define `IdentificationResult` model (track, artist, album, year, artwork URL, confidence)
- [ ] Define `MusicRecognitionProvider` protocol
- [ ] Define `TrackHistory` model
- [ ] Define `AppSettings` model with all configurable values
- [ ] Define `AppState` enum (listening, processing, identified, coolingDown, idle)

### Phase 3: Audio Capture Service
- [ ] `AudioService` - AVAudioEngine-based mic capture
- [ ] Audio preprocessing: mono, 16-bit PCM, configurable sample rate
- [ ] Noise gate (threshold-based)
- [ ] Normalization
- [ ] Rolling buffer (configurable 10-30s, default 20s)
- [ ] Audio level monitoring for debug UI
- [ ] Gap/silence detection for track transitions

### Phase 4: Fingerprinting Service
- [ ] `FingerprintService` - Chromaprint integration strategy
- [ ] Since Chromaprint is a C library, use a Swift wrapper/binding approach
- [ ] Generate fingerprint from audio buffer
- [ ] Fingerprint hashing for duplicate comparison

### Phase 5: Recognition Service
- [ ] `AcoustIDProvider` implementing `MusicRecognitionProvider`
- [ ] AcoustID API integration (fingerprint submission)
- [ ] MusicBrainz metadata resolution (track, artist, album, year)
- [ ] Cover Art Archive integration (album artwork)
- [ ] Stub fallback provider
- [ ] `RecognitionService` orchestrator with provider fallback logic

### Phase 6: Smart Re-detection
- [ ] Duplicate prevention via fingerprint hash comparison
- [ ] Result matching (same track within cooldown → suppress)
- [ ] Global cooldown system (configurable)
- [ ] Per-track cooldown system
- [ ] Similarity threshold for fingerprint comparison

### Phase 7: UI State Management
- [ ] `UIStateManager` (ObservableObject) coordinating all services
- [ ] Detection trigger modes: manual button, automatic interval
- [ ] Countdown timer for next auto-detection
- [ ] Cooldown countdown display
- [ ] History management (last 10 tracks)

### Phase 8: Main App UI
- [ ] App entry point with proper icon setup
- [ ] Main window: fixed size, modern macOS aesthetic
- [ ] Album art display (primary visual)
- [ ] Track title + artist display
- [ ] Confidence indicator (percentage bar)
- [ ] Status indicator (Listening/Processing/Identified/Cooling down)
- [ ] Controls: Start/Stop, Manual Identify, Settings
- [ ] History list (compact, with thumbnails)
- [ ] Settings view (popover/sheet)
- [ ] Color scheme matching the vinyl ear logo

### Phase 9: AirPlay Now Playing Screen
- [ ] Dedicated full-screen `NowPlayingView`
- [ ] Large album art + track/artist
- [ ] Animated background
- [ ] History strip (last 3 tracks)
- [ ] Window management for AirPlay display

### Phase 10: Debug Mode
- [ ] Toggleable debug panel
- [ ] Raw audio levels visualization
- [ ] Buffer fill state
- [ ] Fingerprint generation logs
- [ ] API response viewer (collapsible JSON)
- [ ] Last detection timestamps

### Phase 11: CI/CD & Documentation
- [ ] GitHub Actions workflow (build macOS app)
- [ ] Swift linting step
- [ ] Complete README with setup instructions
- [ ] API key documentation

### Phase 12: Verification
- [ ] Ensure project compiles via `swift build` or `xcodebuild`
- [ ] Verify all modules are properly connected
- [ ] Push to branch

## Architecture Notes

### Project Type
We'll use a **Swift Package Manager** structure with an Xcode project generated or a raw SwiftUI app project structure. Since we can't run Xcode on this machine, we'll create the project files manually for a macOS SwiftUI app that can be opened in Xcode and built.

### Chromaprint Strategy
Chromaprint is a C library. We have two options:
1. Include Chromaprint C source files and bridge them via a C-compatible Swift module
2. Use a pure-Swift fingerprinting approach

We'll go with option 1: include Chromaprint C headers and a Swift wrapper, with the actual C library to be linked at build time. The project will include setup instructions for installing Chromaprint via Homebrew.

### AirPlay Strategy
macOS doesn't have a direct "send to AirPlay" API for custom views. The approach:
- Create a separate `NSWindow` for the Now Playing view
- User can use macOS built-in screen mirroring to send that window/screen to Apple TV
- The window is designed to look great full-screen on a TV

### File Structure
```
RecordInfo/
├── RecordInfo.xcodeproj/
├── RecordInfo/
│   ├── App/
│   │   ├── RecordInfoApp.swift
│   │   └── AppDelegate.swift
│   ├── Models/
│   │   ├── IdentificationResult.swift
│   │   ├── TrackHistory.swift
│   │   └── AppSettings.swift
│   ├── Services/
│   │   ├── AudioService.swift
│   │   ├── FingerprintService.swift
│   │   ├── RecognitionService.swift
│   │   ├── Providers/
│   │   │   ├── MusicRecognitionProvider.swift
│   │   │   ├── AcoustIDProvider.swift
│   │   │   └── StubFallbackProvider.swift
│   │   └── CooldownManager.swift
│   ├── ViewModels/
│   │   └── UIStateManager.swift
│   ├── Views/
│   │   ├── MainView.swift
│   │   ├── NowPlayingView.swift
│   │   ├── HistoryView.swift
│   │   ├── SettingsView.swift
│   │   ├── DebugView.swift
│   │   └── Components/
│   │       ├── AlbumArtView.swift
│   │       ├── ConfidenceIndicator.swift
│   │       └── StatusIndicator.swift
│   ├── Utilities/
│   │   ├── Logger.swift
│   │   └── Constants.swift
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
├── .github/
│   └── workflows/
│       └── build.yml
├── .gitignore
├── LICENSE
└── README.md
```
