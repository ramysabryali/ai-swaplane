import CryptoKit
import XCTest
@testable import SwaplaneCore
@testable import Vault

final class CryptoAndCodecTests: XCTestCase {
    func testSealOpenRoundTrip() throws {
        let key = SnapshotCrypto.newKey()
        let sealed = try SnapshotCrypto.seal(Data("FAKE-SECRET-123".utf8), key: key)
        XCTAssertFalse(String(decoding: sealed, as: UTF8.self).contains("FAKE-SECRET"))
        XCTAssertEqual(String(decoding: try SnapshotCrypto.open(sealed, key: key), as: UTF8.self), "FAKE-SECRET-123")
    }

    func testTamperedAndWrongKeyFail() throws {
        let key = SnapshotCrypto.newKey()
        var sealed = try SnapshotCrypto.seal(Data("payload".utf8), key: key)
        XCTAssertThrowsError(try SnapshotCrypto.open(sealed, key: SnapshotCrypto.newKey()))
        sealed[sealed.count - 1] ^= 0xFF
        XCTAssertThrowsError(try SnapshotCrypto.open(sealed, key: key)) {
            XCTAssertEqual($0 as? SwaplaneError, .snapshotCorrupt)
        }
        XCTAssertThrowsError(try SnapshotCrypto.open(Data("short".utf8), key: key))
    }

    func testNoncesAreFresh() throws {
        let key = SnapshotCrypto.newKey()
        let a = try SnapshotCrypto.seal(Data("same".utf8), key: key)
        let b = try SnapshotCrypto.seal(Data("same".utf8), key: key)
        XCTAssertNotEqual(a, b)
    }

    func testBundleCodecRoundTripAndTruncation() throws {
        let b = StateBundle(
            entries: [.init(path: "a/b.txt", mode: 0o640, data: Data([1, 2, 3])), .init(path: "empty", data: Data())],
            secrets: ["credential": Data("FAKE".utf8)], meta: ["identityKey": "k"])
        let enc = BundleCodec.encode(b)
        XCTAssertEqual(try BundleCodec.decode(enc), b)
        XCTAssertThrowsError(try BundleCodec.decode(enc.dropLast(3)))
        XCTAssertThrowsError(try BundleCodec.decode(Data("XXXX".utf8)))
    }

    func testRedactedNeverPrints() {
        let r = Redacted("FAKE-TOKEN")
        XCTAssertFalse("\(r) \(String(reflecting: r))".contains("FAKE"))
        var dump = ""
        Swift.dump(r, to: &dump)
        XCTAssertFalse(dump.contains("FAKE"))
    }
}
