import Foundation

/// User-presentable errors. Messages must never contain secrets.
public enum SwaplaneError: Error, LocalizedError, Equatable, Sendable {
    case toolNotInstalled(Tool)
    case unsupported(Tool, String)
    case noCredentials(Tool)
    case profileNotFound
    case snapshotCorrupt
    case keychain(Int32)
    case appDidNotQuit(String)
    case verifyFailed(String)
    case switchInProgress(Tool)
    case drift(Tool)
    case invalidBundle(String)
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotInstalled(let t): "\(t.displayName) isn't installed."
        case .unsupported(let t, let why): "\(t.displayName) isn't supported: \(why)"
        case .noCredentials(let t): "No signed-in account found for \(t.displayName)."
        case .profileNotFound: "That profile no longer exists."
        case .snapshotCorrupt: "The saved profile data is damaged and can't be used."
        case .keychain(let s): "Keychain error (code \(s))."
        case .appDidNotQuit(let n): "\(n) didn't quit. Close it and try again."
        case .verifyFailed(let why): "Couldn't confirm the switch: \(why)"
        case .switchInProgress(let t): "A switch for \(t.displayName) is already running."
        case .drift(let t):
            "\(t.displayName) is signed in to a different account than AI Swaplane expected."
        case .invalidBundle(let why): "Invalid profile data: \(why)"
        case .io(let why): "File error: \(why)"
        }
    }
}
