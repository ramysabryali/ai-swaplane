import CryptoKit
import Foundation
import SwaplaneCore

/// AES-256-GCM sealing with an authenticated header. Fresh random nonce per seal.
public enum SnapshotCrypto {
    private static let header = Data("SWPL".utf8) + Data([1])

    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    public static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header)
        guard let combined = box.combined else { throw SwaplaneError.snapshotCorrupt }
        return header + combined
    }

    public static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard sealed.count > header.count + 28, sealed.prefix(header.count) == header else {
            throw SwaplaneError.snapshotCorrupt
        }
        do {
            let box = try AES.GCM.SealedBox(combined: sealed.dropFirst(header.count))
            return try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw SwaplaneError.snapshotCorrupt
        }
    }
}
