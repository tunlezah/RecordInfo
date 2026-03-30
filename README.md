# RecordInfo

A macOS native music recognition app that listens to audio via your microphone, identifies songs using AcoustID/Chromaprint and MusicBrainz, and displays a "Now Playing" interface both locally and on Apple TV via AirPlay.

## Features

- Real-time music recognition using acoustic fingerprinting (Chromaprint/AcoustID)
- Metadata retrieval from MusicBrainz (artist, title, album, release year)
- Album cover art from the Cover Art Archive
- "Now Playing" display with album artwork, track info, and playback context
- AirPlay support to mirror the Now Playing window to Apple TV
- Configurable detection parameters (buffer length, interval, confidence threshold)
- Built with SwiftUI for a native macOS experience
- Continuous listening mode with cooldown to avoid duplicate detections

## Screenshots

<!-- Add screenshots here -->

| Now Playing | Settings |
|:-----------:|:--------:|
| *screenshot* | *screenshot* |

## Requirements

- macOS 26 or later
- Xcode 16 or later
- Swift 6
- Chromaprint library (installed via Homebrew)

## Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/your-username/RecordInfo.git
   cd RecordInfo
   ```

2. Install Chromaprint via Homebrew:

   ```bash
   brew install chromaprint
   ```

3. Open the project in Xcode:

   ```bash
   open RecordInfo.xcodeproj
   ```

4. Build and run (Cmd+R).

## API Keys

### AcoustID

An AcoustID API key is required for music fingerprint lookups.

1. Register a new application at <https://acoustid.org/new-application> to obtain your API key.
2. Launch RecordInfo and open Settings.
3. Enter your AcoustID API key in the provided field.

### MusicBrainz

No API key is required. MusicBrainz is a free and open database. Note that the API is rate-limited to **1 request per second** -- the app respects this limit automatically.

### Cover Art Archive

No API key is required. Cover art is fetched from the Cover Art Archive, which serves album artwork linked to MusicBrainz releases.

## Microphone Permissions

RecordInfo uses `AVAudioEngine` to capture audio from your microphone. On first launch, macOS will prompt you to grant microphone access. You can manage this later in **System Settings > Privacy & Security > Microphone**.

## AirPlay Setup

To display the Now Playing window on your Apple TV:

1. Ensure your Mac and Apple TV are on the same network.
2. Open the Now Playing window in RecordInfo.
3. Use macOS screen mirroring (Control Center > Screen Mirroring) to send the window to your Apple TV.

The Now Playing interface is designed to look great on a large screen.

## Architecture

The app is organized around four core services:

| Service | Responsibility |
|---|---|
| **AudioService** | Manages `AVAudioEngine`, captures microphone input, and provides audio buffers for fingerprinting. |
| **FingerprintService** | Interfaces with the Chromaprint library to generate acoustic fingerprints from raw audio data. |
| **RecognitionService** | Sends fingerprints to the AcoustID API, retrieves metadata from MusicBrainz, and fetches cover art from the Cover Art Archive. |
| **UIStateManager** | Coordinates app state between services and the SwiftUI views, managing the current track display and detection lifecycle. |

## Configuration

The following parameters can be adjusted in the app settings to tune recognition behavior:

| Option | Description | Default |
|---|---|---|
| Buffer length | Duration of audio (in seconds) captured before generating a fingerprint. | 20s (10-30s) |
| Detection interval | How often (in seconds) the app attempts a new recognition. | 120s (30-300s) |
| Confidence threshold | Minimum AcoustID score (0.0 -- 1.0) required to accept a match. | 0.6 |
| Global cooldown | Time (in seconds) after a match before any new detection. | 30s |
| Per-track cooldown | Time (in seconds) before the same track can be detected again. | 300s |
| Auto detection | Automatically scan at the configured interval. | Enabled |
| Gap detection | Detect silence between tracks for transition-aware scanning. | Disabled |
| Fallback provider | Try a fallback provider if primary fails. | Enabled |
| Debug mode | Show debug panel with audio levels, buffer state, and API logs. | Disabled |

## License

This project is licensed under the MIT License.

```
MIT License

Copyright (c) 2025 RecordInfo Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
