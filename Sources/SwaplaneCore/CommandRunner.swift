import Foundation

public struct CommandResult: Sendable {
    public var status: Int32
    public var stdout: String
    public init(status: Int32, stdout: String) {
        self.status = status
        self.stdout = stdout
    }
}

/// Runs short-lived helper commands (e.g. `claude --version`). Injectable for tests.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> CommandResult?
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async
        -> CommandResult?
    {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = Pipe()
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(returning: nil); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                cont.resume(returning: CommandResult(
                    status: p.terminationStatus,
                    stdout: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
