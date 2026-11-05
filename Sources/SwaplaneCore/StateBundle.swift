import Foundation

/// A captured copy of a tool's state: files plus named secret blobs.
/// Secrets (e.g. Keychain item values) live in `secrets`; the bundle is only ever persisted sealed.
public struct StateBundle: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var path: String   // relative, '/'-separated
        public var mode: UInt16
        public var data: Data
        public init(path: String, mode: UInt16 = 0o600, data: Data) {
            self.path = path
            self.mode = mode
            self.data = data
        }
    }

    public var entries: [Entry]
    public var secrets: [String: Data]
    public var meta: [String: String]

    public init(entries: [Entry] = [], secrets: [String: Data] = [:], meta: [String: String] = [:]) {
        self.entries = entries
        self.secrets = secrets
        self.meta = meta
    }
}

/// Compact length-prefixed binary encoding for `StateBundle` (avoids base64 inflation).
public enum BundleCodec {
    private static let magic = Data("SWB1".utf8)

    public static func encode(_ b: StateBundle) -> Data {
        var out = magic
        func u32(_ v: Int) { var x = UInt32(v).bigEndian; out.append(Data(bytes: &x, count: 4)) }
        func blob(_ d: Data) { u32(d.count); out.append(d) }
        func str(_ s: String) { blob(Data(s.utf8)) }

        u32(b.entries.count)
        for e in b.entries {
            str(e.path)
            var m = e.mode.bigEndian
            out.append(Data(bytes: &m, count: 2))
            blob(e.data)
        }
        u32(b.secrets.count)
        for (k, v) in b.secrets.sorted(by: { $0.key < $1.key }) { str(k); blob(v) }
        u32(b.meta.count)
        for (k, v) in b.meta.sorted(by: { $0.key < $1.key }) { str(k); str(v) }
        return out
    }

    public static func decode(_ data: Data) throws -> StateBundle {
        var i = data.startIndex
        func need(_ n: Int) throws {
            guard n >= 0, data.distance(from: i, to: data.endIndex) >= n else {
                throw SwaplaneError.invalidBundle("truncated")
            }
        }
        func u32() throws -> Int {
            try need(4)
            let v = data[i..<i + 4].reduce(0) { ($0 << 8) | Int($1) }
            i += 4
            return v
        }
        func blob() throws -> Data {
            let n = try u32()
            try need(n)
            defer { i += n }
            return Data(data[i..<i + n])
        }
        func str() throws -> String { String(decoding: try blob(), as: UTF8.self) }

        try need(4)
        guard Data(data[i..<i + 4]) == magic else { throw SwaplaneError.invalidBundle("bad magic") }
        i += 4

        var b = StateBundle()
        let ne = try u32()
        for _ in 0..<ne {
            let p = try str()
            try need(2)
            let mode = UInt16(data[i]) << 8 | UInt16(data[i + 1])
            i += 2
            b.entries.append(.init(path: p, mode: mode, data: try blob()))
        }
        let ns = try u32()
        for _ in 0..<ns { let k = try str(); b.secrets[k] = try blob() }
        let nm = try u32()
        for _ in 0..<nm { let k = try str(); b.meta[k] = try str() }
        return b
    }
}
