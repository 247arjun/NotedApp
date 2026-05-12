import Foundation
import os.log

// MARK: - Logging

/// Centralised loggers shared across macOS and iOS targets.
public enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.arjun.Noted"

    public static let note    = Logger(subsystem: subsystem, category: "note")
    public static let persist = Logger(subsystem: subsystem, category: "persistence")
    public static let restore = Logger(subsystem: subsystem, category: "restore")
    public static let window  = Logger(subsystem: subsystem, category: "window")
    public static let editor  = Logger(subsystem: subsystem, category: "editor")
    public static let sync    = Logger(subsystem: subsystem, category: "sync")
}
