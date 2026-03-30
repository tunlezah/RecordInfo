import Foundation
import os

enum LogCategory: String {
    case audio = "Audio"
    case fingerprint = "Fingerprint"
    case recognition = "Recognition"
    case ui = "UI"
    case network = "Network"
    case general = "General"
}

final class AppLogger: Sendable {
    static let shared = AppLogger()

    private let subsystem = "com.recordinfo.app"

    struct LogEntry: Identifiable, Sendable {
        let id = UUID()
        let timestamp: Date
        let category: LogCategory
        let level: OSLogType
        let message: String
    }

    private let _entries = OSAllocatedUnfairLock(initialState: [LogEntry]())
    private let maxEntries = 200

    var entries: [LogEntry] {
        _entries.withLock { $0 }
    }

    private init() {}

    func log(_ message: String, category: LogCategory = .general, level: OSLogType = .info) {
        let logger = os.Logger(subsystem: subsystem, category: category.rawValue)
        logger.log(level: level, "\(message)")

        let entry = LogEntry(timestamp: Date(), category: category, level: level, message: message)
        _entries.withLock { entries in
            entries.append(entry)
            if entries.count > self.maxEntries {
                entries.removeFirst()
            }
        }
    }

    func debug(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .debug)
    }

    func error(_ message: String, category: LogCategory = .general) {
        log(message, category: category, level: .error)
    }

    func clear() {
        _entries.withLock { $0.removeAll() }
    }
}
