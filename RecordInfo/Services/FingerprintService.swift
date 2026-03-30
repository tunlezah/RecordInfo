import CryptoKit
import Foundation

final class FingerprintService: FingerprintServiceProtocol, Sendable {

    // MARK: - Errors

    enum FingerprintError: LocalizedError {
        case fpcalcNotFound
        case tempFileCreationFailed
        case processError(String)
        case noFingerprint
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .fpcalcNotFound:
                return "fpcalc (Chromaprint) not found. Install it via: brew install chromaprint"
            case .tempFileCreationFailed:
                return "Failed to create temporary audio file."
            case .processError(let detail):
                return "fpcalc process error: \(detail)"
            case .noFingerprint:
                return "No fingerprint found in fpcalc output."
            case .invalidOutput:
                return "Could not parse fpcalc output."
            }
        }
    }

    // MARK: - Fingerprint Generation

    /// Generates an audio fingerprint using the Chromaprint `fpcalc` CLI tool.
    /// The audio data should be raw 16-bit signed little-endian PCM (mono).
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String {
        let fpcalcPath = try await locateFpcalc()
        let tempURL = try writeTempWAV(audioData: audioData, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try await runFpcalc(at: fpcalcPath, inputURL: tempURL, duration: duration)
    }

    /// Returns a SHA-256 hash of the fingerprint string, useful for quick equality checks.
    func hashFingerprint(_ fingerprint: String) -> String {
        let data = Data(fingerprint.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares two fingerprint strings and returns a similarity score between 0.0 and 1.0.
    /// Uses character-level comparison as an approximation of true acoustic similarity.
    func compareFingerprints(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }

        let charsA = Array(a)
        let charsB = Array(b)
        let minLength = min(charsA.count, charsB.count)
        let maxLength = max(charsA.count, charsB.count)

        guard maxLength > 0 else { return 0.0 }

        var matches = 0
        for i in 0..<minLength {
            if charsA[i] == charsB[i] {
                matches += 1
            }
        }

        return Double(matches) / Double(maxLength)
    }

    // MARK: - Private Helpers

    private func locateFpcalc() async throws -> String {
        let candidates = [
            "/opt/homebrew/bin/fpcalc",
            "/usr/local/bin/fpcalc",
            "/usr/bin/fpcalc",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try `which` as a last resort
        let whichProcess = Process()
        let pipe = Pipe()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["fpcalc"]
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice

        try whichProcess.run()
        whichProcess.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) else {
            throw FingerprintError.fpcalcNotFound
        }

        return output
    }

    /// Writes raw 16-bit PCM data wrapped in a minimal WAV header to a temporary file.
    private func writeTempWAV(audioData: Data, sampleRate: Int) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("recordinfo_\(UUID().uuidString).wav")

        let header = buildWAVHeader(
            dataSize: UInt32(audioData.count),
            sampleRate: UInt32(sampleRate),
            channels: 1,
            bitsPerSample: 16
        )

        var fileData = Data()
        fileData.append(header)
        fileData.append(audioData)

        guard FileManager.default.createFile(atPath: tempURL.path, contents: fileData) else {
            throw FingerprintError.tempFileCreationFailed
        }

        return tempURL
    }

    private func buildWAVHeader(dataSize: UInt32, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let chunkSize = 36 + dataSize

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(littleEndianUInt32: chunkSize)
        header.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(littleEndianUInt32: 16)              // subchunk1 size
        header.append(littleEndianUInt16: 1)               // audio format (PCM)
        header.append(littleEndianUInt16: channels)
        header.append(littleEndianUInt32: sampleRate)
        header.append(littleEndianUInt32: byteRate)
        header.append(littleEndianUInt16: blockAlign)
        header.append(littleEndianUInt16: bitsPerSample)

        // data subchunk
        header.append(contentsOf: "data".utf8)
        header.append(littleEndianUInt32: dataSize)

        return header
    }

    private func runFpcalc(at path: String, inputURL: URL, duration: Double) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [
            "-raw",
            "-length", String(Int(duration)),
            inputURL.path,
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw FingerprintError.processError(errorString)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        // fpcalc output format:
        //   DURATION=...
        //   FINGERPRINT=...
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("FINGERPRINT=") {
                let fingerprint = String(trimmed.dropFirst("FINGERPRINT=".count))
                guard !fingerprint.isEmpty else {
                    throw FingerprintError.noFingerprint
                }
                return fingerprint
            }
        }

        throw FingerprintError.noFingerprint
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(littleEndianUInt32 value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func append(littleEndianUInt16 value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
