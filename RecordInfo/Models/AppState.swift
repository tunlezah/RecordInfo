import Foundation

enum AppState: Equatable {
    case idle
    case listening
    case processing
    case identified(IdentificationResult)
    case coolingDown(TimeInterval)
    case error(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .identified: return "Identified"
        case .coolingDown(let remaining):
            let seconds = Int(remaining)
            return "Cooldown (\(seconds)s)"
        case .error(let message): return "Error: \(message)"
        }
    }

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.listening, .listening), (.processing, .processing):
            return true
        case (.identified(let lhsResult), .identified(let rhsResult)):
            return lhsResult == rhsResult
        case (.coolingDown(let lhsTime), .coolingDown(let rhsTime)):
            return lhsTime == rhsTime
        case (.error(let lhsMsg), .error(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}
