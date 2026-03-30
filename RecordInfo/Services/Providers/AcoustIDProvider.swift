import Foundation

struct AcoustIDProvider: MusicRecognitionProvider {

    let name = "AcoustID"

    private let apiKey: String
    private let fingerprintService: FingerprintService
    private let session: URLSession

    private static let acoustIDBaseURL = "https://api.acoustid.org/v2/lookup"
    private static let musicBrainzBaseURL = "https://musicbrainz.org/ws/2/recording"
    private static let coverArtBaseURL = "https://coverartarchive.org/release"
    private static let userAgent = "RecordInfo/1.0 (https://github.com/tunlezah/recordinfo)"

    init(apiKey: String, fingerprintService: FingerprintService) {
        self.apiKey = apiKey
        self.fingerprintService = fingerprintService

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": Self.userAgent]
        self.session = URLSession(configuration: config)
    }

    // MARK: - AcoustID Response Models

    struct AcoustIDResponse: Codable {
        let status: String
        let results: [AcoustIDResult]?
    }

    struct AcoustIDResult: Codable {
        let id: String?
        let score: Double?
        let recordings: [AcoustIDRecording]?
    }

    struct AcoustIDRecording: Codable {
        let id: String?
        let title: String?
        let artists: [AcoustIDArtist]?
        let releasegroups: [AcoustIDReleaseGroup]?
    }

    struct AcoustIDArtist: Codable {
        let id: String?
        let name: String?
    }

    struct AcoustIDReleaseGroup: Codable {
        let id: String?
        let title: String?
        let type: String?
    }

    // MARK: - MusicBrainz Response Models

    struct MusicBrainzRecording: Codable {
        let id: String?
        let title: String?
        let releases: [MusicBrainzRelease]?
        let artistCredit: [MusicBrainzArtistCredit]?

        enum CodingKeys: String, CodingKey {
            case id, title, releases
            case artistCredit = "artist-credit"
        }
    }

    struct MusicBrainzRelease: Codable {
        let id: String?
        let title: String?
        let date: String?
        let status: String?
    }

    struct MusicBrainzArtistCredit: Codable {
        let name: String?
        let artist: MusicBrainzArtist?
        let joinphrase: String?
    }

    struct MusicBrainzArtist: Codable {
        let id: String?
        let name: String?
    }

    // MARK: - Errors

    enum AcoustIDError: LocalizedError {
        case emptyAPIKey
        case fingerprintFailed
        case networkError(String)
        case noResults
        case invalidResponse
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .emptyAPIKey:
                return "AcoustID API key is not configured."
            case .fingerprintFailed:
                return "Failed to generate audio fingerprint."
            case .networkError(let detail):
                return "Network error: \(detail)"
            case .noResults:
                return "No matching recordings found."
            case .invalidResponse:
                return "Invalid response from server."
            case .rateLimited:
                return "Rate limited. Please try again later."
            }
        }
    }

    // MARK: - MusicRecognitionProvider

    func identify(audioData: Data, duration: Double, sampleRate: Int) async throws -> IdentificationResult? {
        guard !apiKey.isEmpty else {
            throw AcoustIDError.emptyAPIKey
        }

        let fingerprint: String
        do {
            fingerprint = try await fingerprintService.generateFingerprint(
                from: audioData,
                sampleRate: sampleRate,
                duration: duration
            )
        } catch {
            throw AcoustIDError.fingerprintFailed
        }

        let acoustIDResult = try await lookupAcoustID(fingerprint: fingerprint, duration: duration)

        guard let bestResult = acoustIDResult.results?.first(where: { ($0.score ?? 0) > 0 }),
              let recording = bestResult.recordings?.first,
              let recordingID = recording.id else {
            return nil
        }

        let score = bestResult.score ?? 0.0

        let mbRecording = try await fetchMusicBrainzRecording(id: recordingID)

        let trackTitle = mbRecording.title ?? recording.title ?? "Unknown Title"

        let artist: String = {
            if let credits = mbRecording.artistCredit, !credits.isEmpty {
                return credits.map { credit in
                    let artistName = credit.name ?? credit.artist?.name ?? ""
                    let join = credit.joinphrase ?? ""
                    return artistName + join
                }.joined()
            }
            return recording.artists?.compactMap(\.name).joined(separator: ", ") ?? "Unknown Artist"
        }()

        let release = mbRecording.releases?.first
        let album = release?.title ?? recording.releasegroups?.first?.title ?? "Unknown Album"

        let releaseYear: String? = {
            guard let dateStr = release?.date else { return nil }
            return String(dateStr.prefix(4))
        }()

        var artworkURL: URL? = nil
        if let releaseID = release?.id {
            artworkURL = try? await fetchCoverArtURL(releaseID: releaseID)
        }

        return IdentificationResult(
            trackTitle: trackTitle,
            artist: artist,
            album: album,
            releaseYear: releaseYear,
            artworkURL: artworkURL,
            confidence: score,
            fingerprint: fingerprint,
            provider: name
        )
    }

    // MARK: - API Calls

    private func lookupAcoustID(fingerprint: String, duration: Double) async throws -> AcoustIDResponse {
        var components = URLComponents(string: Self.acoustIDBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "client", value: apiKey),
            URLQueryItem(name: "fingerprint", value: fingerprint),
            URLQueryItem(name: "duration", value: String(Int(duration))),
            URLQueryItem(name: "meta", value: "recordings+releasegroups+compress"),
        ]

        guard let url = components.url else {
            throw AcoustIDError.networkError("Failed to construct AcoustID URL.")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AcoustIDError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AcoustIDError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AcoustIDError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(AcoustIDResponse.self, from: data)

        guard decoded.status == "ok" else {
            throw AcoustIDError.invalidResponse
        }

        return decoded
    }

    private func fetchMusicBrainzRecording(id: String) async throws -> MusicBrainzRecording {
        // Respect MusicBrainz rate limit: ~1 request per second
        try await Task.sleep(for: .seconds(1))

        let urlString = "\(Self.musicBrainzBaseURL)/\(id)?inc=releases+artists&fmt=json"
        guard let url = URL(string: urlString) else {
            throw AcoustIDError.networkError("Failed to construct MusicBrainz URL.")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AcoustIDError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw AcoustIDError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw AcoustIDError.networkError("MusicBrainz HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(MusicBrainzRecording.self, from: data)
    }

    private func fetchCoverArtURL(releaseID: String) async throws -> URL? {
        // Respect rate limit
        try await Task.sleep(for: .seconds(1))

        let urlString = "\(Self.coverArtBaseURL)/\(releaseID)/front"
        guard let url = URL(string: urlString) else {
            return nil
        }

        // Use a HEAD-like approach: the Cover Art Archive redirects to the actual image URL.
        // We follow redirects and use the final URL.
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            return nil
        }

        // The response URL after redirects is the actual image URL.
        return httpResponse.url ?? url
    }
}
