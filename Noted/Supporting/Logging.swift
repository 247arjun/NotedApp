import Foundation
import os.log

// MARK: - Logging

/// Centralised loggers following the diagnostics spec (§28).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.noted.app"

    /// Note lifecycle: creation, close, reopen, delete.
    static let note      = Logger(subsystem: subsystem, category: "note")

    /// Persistence: save, load, flush, failure.
    static let persist   = Logger(subsystem: subsystem, category: "persistence")

    /// Restore: launch restore flow, frame adjustments, fallback.
    static let restore   = Logger(subsystem: subsystem, category: "restore")

    /// Window management: open, close, frame changes.
    static let window    = Logger(subsystem: subsystem, category: "window")

    /// Editor: text changes, formatting.
    static let editor    = Logger(subsystem: subsystem, category: "editor")
}
