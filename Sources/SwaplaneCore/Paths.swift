import Foundation

/// All filesystem locations, resolved from an injectable home directory.
public struct Paths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    // Swaplane's own data (never contains plaintext secrets)
    public var supportDir: URL {
        home.appendingPathComponent("Library/Application Support/Swaplane", isDirectory: true)
    }
    public var snapshotsDir: URL { supportDir.appendingPathComponent("snapshots", isDirectory: true) }
    public var rollbackDir: URL { supportDir.appendingPathComponent("rollback", isDirectory: true) }
    public var profilesFile: URL { supportDir.appendingPathComponent("profiles.json") }
    public var stateFile: URL { supportDir.appendingPathComponent("state.json") }
    public var journalFile: URL { supportDir.appendingPathComponent("journal.json") }
    public var activityLog: URL { supportDir.appendingPathComponent("activity.log") }

    // Third-party tool locations (verified in SPIKE-0, 2026-11-05)
    public var claudeJSON: URL { home.appendingPathComponent(".claude.json") }
    public var claudeDesktopDataDir: URL {
        home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    }
}

public enum FileUtil {
    /// Creates a directory (and parents) with 0700 permissions.
    public static func ensureDir(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }

    /// Writes data atomically (temp file in the same dir + rename) with the given mode.
    public static func atomicWrite(_ data: Data, to url: URL, mode: UInt16 = 0o600) throws {
        let dir = url.deletingLastPathComponent()
        try ensureDir(dir)
        let tmp = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(
            atPath: tmp.path, contents: data, attributes: [.posixPermissions: mode])
        else { throw SwaplaneError.io("couldn't create temporary file") }
        if rename(tmp.path, url.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: tmp)
            throw SwaplaneError.io("couldn't replace file (errno \(code))")
        }
    }

    public static func posixMode(of url: URL) -> UInt16? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.posixPermissions] as? NSNumber)?.uint16Value
    }
}

public enum SwaplaneJSON {
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
