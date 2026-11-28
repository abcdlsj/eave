import CryptoKit
import Foundation
import XCTest
@testable import Eave

final class AutoUpdaterTests: XCTestCase {

    // MARK: - Semver

    func testSemverParsingAndOrdering() {
        XCTAssertEqual(
            AutoUpdater.parseSemver("v0.3.0"),
            AutoUpdater.Semver(major: 0, minor: 3, patch: 0)
        )
        XCTAssertEqual(
            AutoUpdater.parseSemver("0.4.1-rc.1"),
            AutoUpdater.Semver(major: 0, minor: 4, patch: 1)
        )
        XCTAssertEqual(
            AutoUpdater.parseSemver("1.2"),
            AutoUpdater.Semver(major: 1, minor: 2, patch: 0)
        )
        XCTAssertTrue(AutoUpdater.parseSemver("0.4.0")! > AutoUpdater.parseSemver("0.3.9")!)
        XCTAssertTrue(AutoUpdater.parseSemver("1.0.0")! > AutoUpdater.parseSemver("0.99.99")!)
        XCTAssertNil(AutoUpdater.parseSemver("dev"))
        XCTAssertNil(AutoUpdater.parseSemver(""))
    }

    // MARK: - CryptoKit Ed25519 Verification

    func testEmbeddedPublicKeyDecodesCleanly() throws {
        let key = try AutoUpdater.decodeVerifyingKey(AutoUpdater.embeddedPublicKeyBase64)
        XCTAssertEqual(key.rawRepresentation.count, 32)
    }

    func testEd25519VerifyAcceptsValidAndRejectsTampered() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubB64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let decodedPub = try AutoUpdater.decodeVerifyingKey(pubB64)

        let payload = AutoUpdater.canonicalAssetPayload(
            app: "eave",
            version: "0.4.0",
            platform: "darwin-universal",
            sha256Hex: "deadbeef0123456789abcdef",
            size: 123_456
        )
        XCTAssertEqual(payload, "v1:eave:0.4.0:darwin-universal:deadbeef0123456789abcdef:123456")

        let payloadData = Data(payload.utf8)
        let signature = try privateKey.signature(for: payloadData)
        let sigB64 = signature.base64EncodedString()

        XCTAssertNoThrow(
            try AutoUpdater.verifyEd25519(
                publicKey: decodedPub,
                message: payloadData,
                signatureBase64: sigB64
            )
        )

        XCTAssertThrowsError(
            try AutoUpdater.verifyEd25519(
                publicKey: decodedPub,
                message: Data("tampered".utf8),
                signatureBase64: sigB64
            )
        )

        // Manifest bytes verification
        let manifestBytes = Data("{\"app\":\"eave\",\"schema_version\":1}\n".utf8)
        let manifestSig = try privateKey.signature(for: manifestBytes).base64EncodedString()
        XCTAssertNoThrow(
            try AutoUpdater.verifyEd25519(
                publicKey: decodedPub,
                message: manifestBytes,
                signatureBase64: manifestSig + "\n"
            )
        )
        XCTAssertThrowsError(
            try AutoUpdater.verifyEd25519(
                publicKey: decodedPub,
                message: Data("{\"app\":\"other\",\"schema_version\":1}\n".utf8),
                signatureBase64: manifestSig
            )
        )
    }

    // MARK: - URL Allowlist

    func testURLAllowlistBlocksUntrustedHosts() {
        XCTAssertNoThrow(
            try AutoUpdater.validateDownloadURL(
                "https://github.com/abcdlsj/eave/releases/latest/download/latest.json",
                allowLocalhost: false
            )
        )
        XCTAssertNoThrow(
            try AutoUpdater.validateDownloadURL(
                "https://objects.githubusercontent.com/github-production-release-asset/123",
                allowLocalhost: false
            )
        )
        XCTAssertNoThrow(
            try AutoUpdater.validateDownloadURL(
                "https://release-assets.githubusercontent.com/github-production-release-asset/456",
                allowLocalhost: false
            )
        )
        XCTAssertThrowsError(
            try AutoUpdater.validateDownloadURL(
                "https://github.com/evil/eave/releases/latest/download/latest.json",
                allowLocalhost: false
            )
        )
        XCTAssertThrowsError(
            try AutoUpdater.validateDownloadURL(
                "https://evil.example.com/latest.json",
                allowLocalhost: false
            )
        )
        XCTAssertThrowsError(
            try AutoUpdater.validateDownloadURL(
                "http://127.0.0.1:8080/latest.json",
                allowLocalhost: false
            )
        )
        XCTAssertNoThrow(
            try AutoUpdater.validateDownloadURL(
                "http://127.0.0.1:8080/latest.json",
                allowLocalhost: true
            )
        )
        XCTAssertNoThrow(
            try AutoUpdater.validateDownloadURL(
                "http://localhost:9000/latest.json",
                allowLocalhost: true
            )
        )
    }

    // MARK: - Bundle Path Inspection

    func testInspectBundlePathRejectsDMGTranslocationAndAcceptsWritableApp() throws {
        let dmgExe = URL(fileURLWithPath: "/Volumes/Eave/Eave.app/Contents/MacOS/Eave")
        let dmgResult = AutoUpdater.inspectAppBundlePath(dmgExe)
        XCTAssertNil(dmgResult.appURL)
        XCTAssertFalse(dmgResult.isWritable)

        let translocatedExe = URL(
            fileURLWithPath: "/private/var/folders/xx/AppTranslocation/ABC/d/Eave.app/Contents/MacOS/Eave"
        )
        let transResult = AutoUpdater.inspectAppBundlePath(translocatedExe)
        XCTAssertNil(transResult.appURL)
        XCTAssertFalse(transResult.isWritable)

        let nonBundleExe = URL(fileURLWithPath: "/usr/local/bin/eave")
        let nonBundleResult = AutoUpdater.inspectAppBundlePath(nonBundleExe)
        XCTAssertNil(nonBundleResult.appURL)
        XCTAssertFalse(nonBundleResult.isWritable)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("eave-updater-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let macOSDir = tempDir
            .appendingPathComponent("Eave.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let exeURL = macOSDir.appendingPathComponent("Eave")
        try Data("bin".utf8).write(to: exeURL)

        let okResult = AutoUpdater.inspectAppBundlePath(exeURL)
        XCTAssertTrue(okResult.isWritable)
        XCTAssertEqual(okResult.appURL?.lastPathComponent, "Eave.app")
    }

    // MARK: - One-Shot Handoff & TTL

    func testHandoffRoundtripIsOneShotAndRespectsTTL() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("eave-handoff-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let handoffURL = tempDir.appendingPathComponent("update-handoff.json")
        let now = AutoUpdater.nowEpochMs()
        let payload = AutoUpdater.UpdateHandoffPayload(
            schemaVersion: 1,
            fromVersion: "0.3.0",
            toVersion: "0.4.0",
            createdAtMs: now,
            ttlMs: AutoUpdater.handoffTTLMs,
            settingsWindowOpen: true,
            selectedSettingsTab: "Shortcuts"
        )

        try AutoUpdater.writeHandoffFile(at: handoffURL, payload: payload)
        let consumed = AutoUpdater.consumeHandoffFile(at: handoffURL, nowMs: now + 5_000)
        XCTAssertEqual(consumed, payload)

        // One-shot: second consume returns nil and file is deleted.
        XCTAssertNil(AutoUpdater.consumeHandoffFile(at: handoffURL, nowMs: now + 5_001))
        XCTAssertFalse(FileManager.default.fileExists(atPath: handoffURL.path))

        // Expired handoff is discarded.
        let expired = AutoUpdater.UpdateHandoffPayload(
            schemaVersion: 1,
            fromVersion: "0.3.0",
            toVersion: "0.4.0",
            createdAtMs: 1_000,
            ttlMs: 120_000,
            settingsWindowOpen: true,
            selectedSettingsTab: "General"
        )
        try AutoUpdater.writeHandoffFile(at: handoffURL, payload: expired)
        XCTAssertNil(AutoUpdater.consumeHandoffFile(at: handoffURL, nowMs: 200_000))
        XCTAssertFalse(FileManager.default.fileExists(atPath: handoffURL.path))
    }

    // MARK: - Platform Asset Resolution

    func testResolvePlatformAssetMatchesUniversal() {
        let asset = AutoUpdater.PlatformAsset(
            url: "https://github.com/abcdlsj/eave/releases/download/v0.4.0/eave_0.4.0_darwin_universal.zip",
            signature: "sig",
            sha256: "abc",
            size: 1024,
            format: "app-zip",
            bundleName: "Eave.app",
            bundleID: "com.abcdlsj.eave"
        )
        let resolved = AutoUpdater.resolvePlatformAsset(["darwin-universal": asset])
        XCTAssertEqual(resolved?.platformKey, "darwin-universal")
        XCTAssertEqual(resolved?.asset, asset)
    }
}
