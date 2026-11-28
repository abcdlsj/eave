import AppKit
import CryptoKit
import Darwin
import Foundation
import Observation

/// Seamless auto-update manager for Eave.
///
/// Fetches signed `latest.json` + `latest.json.sig` directly from GitHub Releases CDN,
/// verifies RFC 8032 Ed25519 signatures via Apple CryptoKit and streamed SHA-256 digests,
/// writes an atomic `update-handoff.json` before exit, and hands off post-exit atomic
/// `.app` replacement (preserving local signing identity when present) to a detached helper.
@MainActor
@Observable
final class AutoUpdater {
    nonisolated static let appSlug = "eave"
    nonisolated static let repoSlug = "abcdlsj/eave"
    nonisolated static let expectedBundleID = "com.abcdlsj.eave"
    nonisolated static let expectedBundleName = "Eave.app"
    nonisolated static let embeddedPublicKeyBase64 = "z6LlDdM6xudmzjzE0/1gJtywT7YN4ok/XQ4dwiYt/kw="

    nonisolated static let initialCheckDelaySeconds: TimeInterval = 18
    nonisolated static let checkIntervalSeconds: TimeInterval = 6 * 3600
    nonisolated static let manualCheckCooldownSeconds: TimeInterval = 30
    nonisolated static let autoRestartMaxWaitSeconds: TimeInterval = 8
    nonisolated static let maxManifestBytes: Int = 1 << 20 // 1 MiB
    nonisolated static let maxAssetBytes: UInt64 = 512 << 20 // 512 MiB
    nonisolated static let handoffTTLMs: UInt64 = 120_000 // 2 minutes

    // MARK: - Public Types

    enum UpdatePhase: String, Equatable, Sendable {
        case idle
        case checking
        case available
        case downloading
        case verifying
        case readyToRestart
        case installing
        case error
    }

    struct UpdateStatus: Equatable, Sendable {
        var current: String
        var latest: String?
        var available: Bool
        var phase: UpdatePhase
        var progress: Int
        var canApply: Bool
        var releaseURL: String?
        var notes: String?
        var error: String?
    }

    struct UpdateHandoffPayload: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let fromVersion: String
        let toVersion: String
        let createdAtMs: UInt64
        let ttlMs: UInt64
        let settingsWindowOpen: Bool
        let selectedSettingsTab: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case fromVersion = "from_version"
            case toVersion = "to_version"
            case createdAtMs = "created_at_ms"
            case ttlMs = "ttl_ms"
            case settingsWindowOpen = "settings_window_open"
            case selectedSettingsTab = "selected_settings_tab"
        }
    }

    struct Semver: Comparable, Equatable, CustomStringConvertible, Sendable {
        let major: UInt64
        let minor: UInt64
        let patch: UInt64

        var description: String {
            "\(major).\(minor).\(patch)"
        }

        static func < (lhs: Semver, rhs: Semver) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            return lhs.patch < rhs.patch
        }
    }

    struct ReleaseManifest: Decodable, Sendable {
        let schemaVersion: Int
        let app: String
        let version: String
        let releaseURL: String?
        let notes: String?
        let platforms: [String: PlatformAsset]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case app
            case version
            case releaseURL = "release_url"
            case notes
            case platforms
        }
    }

    struct PlatformAsset: Decodable, Equatable, Sendable {
        let url: String
        let signature: String
        let sha256: String
        let size: UInt64
        let format: String?
        let bundleName: String?
        let bundleID: String?

        enum CodingKeys: String, CodingKey {
            case url
            case signature
            case sha256
            case size
            case format
            case bundleName = "bundle_name"
            case bundleID = "bundle_id"
        }
    }

    struct UpdateMenuDescriptor: Equatable, Sendable {
        let title: String
        let symbol: String
        let isEnabled: Bool
    }

    enum UpdaterError: LocalizedError, Sendable {
        case invalidPublicKey(String)
        case invalidSignature(String)
        case untrustedURL(String)
        case httpError(String)
        case manifestInvalid(String)
        case verificationFailed(String)
        case bundleInvalid(String)
        case ioError(String)

        var errorDescription: String? {
            switch self {
            case .invalidPublicKey(let msg),
                 .invalidSignature(let msg),
                 .untrustedURL(let msg),
                 .httpError(let msg),
                 .manifestInvalid(let msg),
                 .verificationFailed(let msg),
                 .bundleInvalid(let msg),
                 .ioError(let msg):
                return msg
            }
        }
    }

    private struct SelectedRelease: Sendable {
        let version: String
        let platformKey: String
        let asset: PlatformAsset
    }

    private struct StagedUpdate: Sendable {
        let version: String
        let stageDir: URL
        let stagedApp: URL
    }

    // MARK: - Observable State

    private(set) var status: UpdateStatus
    private(set) var lastCheckedAt: Date?
    private(set) var upToDateFeedbackVisible: Bool = false

    /// Returns true while an active modal, shortcut recording, drag, or onboarding flow should defer auto-restart.
    var isAutoRestartBlocked: (() -> Bool)?
    /// Captures lightweight UI context to persist into `update-handoff.json` before exit.
    var captureHandoffContext: (() -> (settingsWindowOpen: Bool, selectedSettingsTab: String?))?

    // MARK: - Internal Configuration & Tasks

    private let currentRaw: String
    private let currentVer: Semver?
    private let manifestURL: String
    private let allowLocalhost: Bool
    private let publicKey: Curve25519.Signing.PublicKey
    private let cacheDir: URL
    private let handoffURL: URL
    private let targetAppURL: URL?
    private let selfUpdatable: Bool

    private var etag: String?
    private var lastCheckMonotonic: CFAbsoluteTime?
    private var selected: SelectedRelease?
    private var staged: StagedUpdate?
    private var startupHandoff: UpdateHandoffPayload?
    private var autoRestartAfterDownload = false

    private var backgroundTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var autoRestartTask: Task<Void, Never>?
    private var upToDateFeedbackTask: Task<Void, Never>?

    init(
        appVersion: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dataDir: URL? = nil,
        cacheDir: URL? = nil,
        executableURL: URL? = Bundle.main.executableURL
    ) {
        let bundleVersion = appVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0.0.0"

        let envVersion = environment["EAVE_UPDATE_TEST_VERSION"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawVer = (envVersion?.isEmpty == false) ? envVersion! : bundleVersion
        let parsedVer = Self.parseSemver(rawVer)
        let displayVer = parsedVer?.description ?? rawVer

        let envManifest = environment["EAVE_UPDATE_MANIFEST_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let custom = envManifest, !custom.isEmpty {
            self.manifestURL = custom
            self.allowLocalhost = true
        } else {
            self.manifestURL = "https://github.com/\(Self.repoSlug)/releases/latest/download/latest.json"
            self.allowLocalhost = false
        }

        let envPubKey = environment["EAVE_UPDATE_TEST_PUBKEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pubKeyB64 = (envPubKey?.isEmpty == false) ? envPubKey! : Self.embeddedPublicKeyBase64
        guard let decodedKey = try? Self.decodeVerifyingKey(pubKeyB64) else {
            preconditionFailure("Embedded updater Ed25519 public key must be valid")
        }
        self.publicKey = decodedKey

        let resolvedDataDir = dataDir ?? Self.defaultDataDirectory()
        let resolvedCacheDir = (cacheDir ?? Self.defaultCacheDirectory())
            .appendingPathComponent("updates", isDirectory: true)

        self.currentRaw = rawVer
        self.currentVer = parsedVer
        self.handoffURL = resolvedDataDir.appendingPathComponent("update-handoff.json")
        self.cacheDir = resolvedCacheDir

        if let exeURL = executableURL {
            let inspection = Self.inspectAppBundlePath(exeURL)
            self.targetAppURL = inspection.appURL
            self.selfUpdatable = inspection.isWritable
        } else {
            self.targetAppURL = nil
            self.selfUpdatable = false
        }

        // Consume any pending handoff file once on startup so a broken restore can never crash-loop.
        self.startupHandoff = Self.consumeHandoffFile(at: self.handoffURL)
        Self.cleanupStaleStaging(in: resolvedCacheDir)

        self.status = UpdateStatus(
            current: displayVer,
            latest: nil,
            available: false,
            phase: .idle,
            progress: 0,
            canApply: false,
            releaseURL: nil,
            notes: nil,
            error: nil
        )
    }

    // MARK: - Lifecycle

    func takeStartupHandoff() -> UpdateHandoffPayload? {
        defer { startupHandoff = nil }
        return startupHandoff
    }

    func startBackgroundChecker(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard currentVer != nil else { return }
        #if DEBUG
        let hasOverride = !(environment["EAVE_UPDATE_MANIFEST_URL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(environment["EAVE_UPDATE_TEST_VERSION"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasOverride else { return }
        #endif
        guard backgroundTask == nil else { return }

        backgroundTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.initialCheckDelaySeconds))
            while !Task.isCancelled {
                await self?.performCheck(manual: false)
                try? await Task.sleep(for: .seconds(Self.checkIntervalSeconds))
            }
        }
    }

    func stop() {
        backgroundTask?.cancel()
        backgroundTask = nil
        checkTask?.cancel()
        checkTask = nil
        downloadTask?.cancel()
        downloadTask = nil
        autoRestartTask?.cancel()
        autoRestartTask = nil
        upToDateFeedbackTask?.cancel()
        upToDateFeedbackTask = nil
    }

    // MARK: - Menu & User Actions

    /// Returns a menu descriptor ONLY when an update is actionable, in progress, or errored; nil when idle/checking.
    var menuDescriptor: UpdateMenuDescriptor? {
        let verLabel = status.latest.map { "v\($0)" } ?? "Update"
        switch status.phase {
        case .idle, .checking:
            return nil
        case .available:
            let title = status.canApply ? "Update to \(verLabel)…" : "Download \(verLabel)…"
            return UpdateMenuDescriptor(title: title, symbol: "arrow.down.circle", isEnabled: true)
        case .downloading:
            return UpdateMenuDescriptor(
                title: "Downloading \(verLabel)… \(status.progress)%",
                symbol: "arrow.down.circle",
                isEnabled: false
            )
        case .verifying:
            return UpdateMenuDescriptor(
                title: "Verifying \(verLabel)…",
                symbol: "checkmark.shield",
                isEnabled: false
            )
        case .readyToRestart:
            return UpdateMenuDescriptor(
                title: "Restart to \(verLabel)",
                symbol: "arrow.clockwise.circle",
                isEnabled: true
            )
        case .installing:
            return UpdateMenuDescriptor(
                title: "Installing \(verLabel)…",
                symbol: "arrow.clockwise.circle",
                isEnabled: false
            )
        case .error:
            return UpdateMenuDescriptor(
                title: "Update Failed — Retry",
                symbol: "exclamationmark.circle",
                isEnabled: true
            )
        }
    }

    func checkForUpdatesManually() {
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            defer { self?.checkTask = nil }
            await self?.performCheck(manual: true)
        }
    }

    /// Primary click handler shared by the menu bar item and Settings UpdatePill.
    func handlePrimaryUpdateAction() {
        switch status.phase {
        case .available:
            if status.canApply {
                startDownload(autoRestart: true)
            } else if let urlStr = status.releaseURL, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case .readyToRestart:
            commitRestart()
        case .error:
            if status.canApply, selected != nil {
                startDownload(autoRestart: true)
            } else {
                checkForUpdatesManually()
            }
        case .downloading, .verifying:
            autoRestartAfterDownload = true
        case .idle:
            checkForUpdatesManually()
        case .checking, .installing:
            break
        }
    }

    func startDownload(autoRestart: Bool = false) {
        switch status.phase {
        case .downloading, .verifying, .installing:
            if autoRestart { autoRestartAfterDownload = true }
            return
        case .readyToRestart:
            if autoRestart {
                scheduleAutoRestartWithinWindow()
            }
            return
        case .idle, .checking, .available, .error:
            break
        }

        guard status.available, status.canApply, let selected else {
            if let urlStr = status.releaseURL, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        autoRestartAfterDownload = autoRestart
        status.phase = .downloading
        status.progress = 0
        status.error = nil

        let cacheDir = self.cacheDir
        let allowLocalhost = self.allowLocalhost
        let pubKey = self.publicKey
        let userAgent = "Eave/\(self.currentRaw)"

        let progressHandler: @Sendable (Int) -> Void = { [weak self] pct in
            Task { @MainActor [weak self] in
                guard let self, self.status.phase == .downloading else { return }
                self.status.progress = pct
            }
        }
        let verifyingHandler: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.status.phase == .downloading else { return }
                self.status.phase = .verifying
                self.status.progress = 100
            }
        }

        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            do {
                let stagedUpdate = try await Self.downloadVerifyAndStage(
                    selected: selected,
                    cacheDir: cacheDir,
                    allowLocalhost: allowLocalhost,
                    publicKey: pubKey,
                    userAgent: userAgent,
                    onProgress: progressHandler,
                    onEnterVerifying: verifyingHandler
                )
                guard !Task.isCancelled, let self else { return }
                self.staged = stagedUpdate
                self.status.phase = .readyToRestart
                self.status.progress = 100
                self.status.error = nil

                if self.autoRestartAfterDownload {
                    self.scheduleAutoRestartWithinWindow()
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.autoRestartAfterDownload = false
                self.status.phase = .error
                self.status.progress = 0
                self.status.error = error.localizedDescription
            }
        }
    }

    func commitRestart() {
        autoRestartTask?.cancel()
        autoRestartTask = nil
        autoRestartAfterDownload = false

        guard let staged, let targetAppURL else {
            status.phase = .error
            status.error = "No verified staged update ready to install"
            return
        }

        status.phase = .installing
        status.progress = 100
        status.error = nil

        let context = captureHandoffContext?() ?? (settingsWindowOpen: false, selectedSettingsTab: nil)
        let handoff = UpdateHandoffPayload(
            schemaVersion: 1,
            fromVersion: status.current,
            toVersion: staged.version,
            createdAtMs: Self.nowEpochMs(),
            ttlMs: Self.handoffTTLMs,
            settingsWindowOpen: context.settingsWindowOpen,
            selectedSettingsTab: context.selectedSettingsTab
        )

        do {
            try Self.writeHandoffFile(at: handoffURL, payload: handoff)
            try Self.spawnDetachedApplyHelper(
                oldPID: ProcessInfo.processInfo.processIdentifier,
                targetApp: targetAppURL,
                stagedApp: staged.stagedApp,
                stageDir: staged.stageDir,
                expectedBundleID: Self.expectedBundleID
            )
            NSApp.terminate(nil)
        } catch {
            status.phase = .error
            status.error = error.localizedDescription
        }
    }

    // MARK: - Private Check & Auto-Restart Coordination

    private func performCheck(manual: Bool) async {
        guard let currentVer else { return }

        if manual,
           status.phase != .error,
           let last = lastCheckMonotonic,
           (CFAbsoluteTimeGetCurrent() - last) < Self.manualCheckCooldownSeconds {
            if !status.available {
                flashUpToDateFeedback()
            }
            return
        }

        switch status.phase {
        case .checking, .downloading, .verifying, .readyToRestart, .installing:
            return
        case .idle, .available, .error:
            break
        }

        let prevPhase = status.phase
        let requestETag = manual ? nil : etag
        status.phase = .checking
        if manual {
            status.error = nil
            upToDateFeedbackVisible = false
        }

        let manifestURL = self.manifestURL
        let allowLocalhost = self.allowLocalhost
        let pubKey = self.publicKey
        let userAgent = "Eave/\(self.currentRaw)"

        do {
            let result = try await Self.fetchVerifiedManifest(
                manifestURL: manifestURL,
                allowLocalhost: allowLocalhost,
                publicKey: pubKey,
                userAgent: userAgent,
                etag: requestETag
            )

            guard status.phase == .checking else { return }
            lastCheckMonotonic = CFAbsoluteTimeGetCurrent()
            lastCheckedAt = Date()

            guard let (manifest, newETag) = result else {
                // 304 Not Modified
                status.phase = prevPhase
                return
            }

            if let newETag {
                etag = newETag
            }

            if let latestVer = Self.parseSemver(manifest.version), latestVer > currentVer {
                let releaseURL = manifest.releaseURL
                    ?? "https://github.com/\(Self.repoSlug)/releases/tag/v\(latestVer)"
                let resolved = Self.resolvePlatformAsset(manifest.platforms)

                status.latest = latestVer.description
                status.available = true
                status.releaseURL = releaseURL
                status.notes = manifest.notes
                status.error = nil
                status.progress = 0
                status.phase = .available

                if let resolved {
                    selected = SelectedRelease(
                        version: latestVer.description,
                        platformKey: resolved.platformKey,
                        asset: resolved.asset
                    )
                    status.canApply = selfUpdatable
                } else {
                    selected = nil
                    status.canApply = false
                }
            } else {
                selected = nil
                status.latest = manifest.version
                status.available = false
                status.canApply = false
                status.error = nil
                status.phase = .idle
                if manual {
                    flashUpToDateFeedback()
                }
            }
        } catch {
            guard status.phase == .checking else { return }
            if manual {
                status.phase = prevPhase == .available ? .available : .error
                status.error = error.localizedDescription
            } else {
                // Silent on background checks.
                status.phase = prevPhase
            }
        }
    }

    private func flashUpToDateFeedback() {
        upToDateFeedbackTask?.cancel()
        upToDateFeedbackVisible = true
        upToDateFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.upToDateFeedbackVisible = false
        }
    }

    private func isBlockedForAutoRestart() -> Bool {
        if NSApp.modalWindow != nil { return true }
        if NSEvent.pressedMouseButtons != 0 { return true }
        return isAutoRestartBlocked?() ?? false
    }

    private func scheduleAutoRestartWithinWindow() {
        autoRestartTask?.cancel()
        autoRestartTask = Task { [weak self] in
            let deadline = CFAbsoluteTimeGetCurrent() + Self.autoRestartMaxWaitSeconds
            // Brief beat so the user registers completion before exit.
            try? await Task.sleep(for: .milliseconds(350))
            while !Task.isCancelled {
                guard let self, self.status.phase == .readyToRestart else { return }
                if !self.isBlockedForAutoRestart() {
                    self.commitRestart()
                    return
                }
                if CFAbsoluteTimeGetCurrent() >= deadline {
                    // Stay cleanly at "Restart to vX.Y.Z" so user is never interrupted.
                    self.autoRestartAfterDownload = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    // MARK: - Network & Verification (Off-Main)

    private nonisolated static func fetchVerifiedManifest(
        manifestURL: String,
        allowLocalhost: Bool,
        publicKey: Curve25519.Signing.PublicKey,
        userAgent: String,
        etag: String?
    ) async throws -> (ReleaseManifest, String?)? {
        try validateDownloadURL(manifestURL, allowLocalhost: allowLocalhost)
        guard let url = URL(string: manifestURL) else {
            throw UpdaterError.untrustedURL("Invalid manifest URL")
        }

        let delegate = AllowlistRedirectDelegate(allowLocalhost: allowLocalhost)
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (manifestData, rawResp) = try await session.data(for: req)
        guard let httpResp = rawResp as? HTTPURLResponse else {
            throw UpdaterError.httpError("Invalid manifest HTTP response")
        }
        if httpResp.statusCode == 304 {
            return nil
        }
        guard httpResp.statusCode == 200 else {
            throw UpdaterError.httpError("Manifest returned HTTP \(httpResp.statusCode)")
        }
        guard manifestData.count <= maxManifestBytes else {
            throw UpdaterError.manifestInvalid("Manifest exceeds maximum allowed size")
        }

        let newETag = httpResp.value(forHTTPHeaderField: "ETag")

        let sigURLString = "\(manifestURL).sig"
        try validateDownloadURL(sigURLString, allowLocalhost: allowLocalhost)
        guard let sigURL = URL(string: sigURLString) else {
            throw UpdaterError.untrustedURL("Invalid manifest signature URL")
        }
        var sigReq = URLRequest(url: sigURL)
        sigReq.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (sigData, rawSigResp) = try await session.data(for: sigReq)
        guard let httpSigResp = rawSigResp as? HTTPURLResponse, httpSigResp.statusCode == 200 else {
            let code = (rawSigResp as? HTTPURLResponse)?.statusCode ?? 0
            throw UpdaterError.httpError("Manifest signature returned HTTP \(code)")
        }
        guard sigData.count <= 4096,
              let sigText = String(data: sigData, encoding: .utf8) else {
            throw UpdaterError.invalidSignature("Manifest signature payload invalid")
        }

        // Verify exact raw manifest bytes against companion `.sig` file.
        try verifyEd25519(publicKey: publicKey, message: manifestData, signatureBase64: sigText)

        let manifest: ReleaseManifest
        do {
            manifest = try JSONDecoder().decode(ReleaseManifest.self, from: manifestData)
        } catch {
            throw UpdaterError.manifestInvalid("Parse manifest JSON failed: \(error.localizedDescription)")
        }

        guard manifest.schemaVersion == 1 else {
            throw UpdaterError.manifestInvalid("Unsupported manifest schema_version \(manifest.schemaVersion)")
        }
        guard manifest.app == appSlug else {
            throw UpdaterError.manifestInvalid("Manifest app mismatch: \(manifest.app)")
        }

        return (manifest, newETag)
    }

    private nonisolated static func downloadVerifyAndStage(
        selected: SelectedRelease,
        cacheDir: URL,
        allowLocalhost: Bool,
        publicKey: Curve25519.Signing.PublicKey,
        userAgent: String,
        onProgress: @escaping @Sendable (Int) -> Void,
        onEnterVerifying: @escaping @Sendable () -> Void
    ) async throws -> StagedUpdate {
        try validateDownloadURL(selected.asset.url, allowLocalhost: allowLocalhost)
        guard selected.asset.size > 0 && selected.asset.size <= maxAssetBytes else {
            throw UpdaterError.verificationFailed("Release asset size out of allowed bounds")
        }

        let fm = FileManager.default
        let stageDir = cacheDir.appendingPathComponent(selected.version, isDirectory: true)
        try? fm.removeItem(at: stageDir)
        do {
            try fm.createDirectory(at: stageDir, withIntermediateDirectories: true)
        } catch {
            throw UpdaterError.ioError("Create update staging dir: \(error.localizedDescription)")
        }

        let archiveURL = stageDir.appendingPathComponent("update.archive")
        do {
            guard let downloadURL = URL(string: selected.asset.url) else {
                throw UpdaterError.untrustedURL("Invalid download URL")
            }

            let downloader = StreamingFileDownloader(
                allowLocalhost: allowLocalhost,
                maxBytes: maxAssetBytes,
                expectedSize: selected.asset.size,
                destinationURL: archiveURL,
                onProgress: onProgress
            )
            let (gotSha256, gotSize) = try await downloader.download(from: downloadURL, userAgent: userAgent)

            onEnterVerifying()

            guard gotSize == selected.asset.size else {
                throw UpdaterError.verificationFailed(
                    "Archive size mismatch (got \(gotSize), expected \(selected.asset.size))"
                )
            }
            guard gotSha256.caseInsensitiveCompare(selected.asset.sha256) == .orderedSame else {
                throw UpdaterError.verificationFailed("Archive SHA-256 checksum mismatch")
            }

            let canonical = canonicalAssetPayload(
                app: appSlug,
                version: selected.version,
                platform: selected.platformKey,
                sha256Hex: gotSha256,
                size: gotSize
            )
            try verifyEd25519(
                publicKey: publicKey,
                message: Data(canonical.utf8),
                signatureBase64: selected.asset.signature
            )

            let bundleName = selected.asset.bundleName ?? expectedBundleName
            let bundleID = selected.asset.bundleID ?? expectedBundleID
            guard bundleID == expectedBundleID else {
                throw UpdaterError.bundleInvalid("Manifest bundle ID does not match Eave")
            }

            let stagedApp = try extractAndVerifyBundle(
                archiveURL: archiveURL,
                stageDir: stageDir,
                format: selected.asset.format ?? "app-zip",
                bundleName: bundleName,
                expectedBundleID: bundleID
            )

            return StagedUpdate(version: selected.version, stageDir: stageDir, stagedApp: stagedApp)
        } catch {
            try? fm.removeItem(at: stageDir)
            throw error
        }
    }

    // MARK: - Pure Verification, Semver & Filesystem Helpers

    nonisolated static func canonicalAssetPayload(
        app: String,
        version: String,
        platform: String,
        sha256Hex: String,
        size: UInt64
    ) -> String {
        "v1:\(app):\(version):\(platform):\(sha256Hex):\(size)"
    }

    nonisolated static func decodeVerifyingKey(_ base64: String) throws -> Curve25519.Signing.PublicKey {
        let trimmed = base64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Data(base64Encoded: trimmed) else {
            throw UpdaterError.invalidPublicKey("Invalid base64 public key")
        }
        guard raw.count == 32 else {
            throw UpdaterError.invalidPublicKey("Ed25519 public key must be 32 bytes")
        }
        do {
            return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        } catch {
            throw UpdaterError.invalidPublicKey("Invalid Ed25519 public key: \(error.localizedDescription)")
        }
    }

    nonisolated static func verifyEd25519(
        publicKey: Curve25519.Signing.PublicKey,
        message: Data,
        signatureBase64: String
    ) throws {
        let trimmed = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sigData = Data(base64Encoded: trimmed) else {
            throw UpdaterError.invalidSignature("Invalid base64 signature")
        }
        guard sigData.count == 64 else {
            throw UpdaterError.invalidSignature("Ed25519 signature must be 64 bytes")
        }
        guard publicKey.isValidSignature(sigData, for: message) else {
            throw UpdaterError.invalidSignature("Ed25519 signature mismatch")
        }
    }

    nonisolated static func validateDownloadURL(_ urlString: String, allowLocalhost: Bool) throws {
        if allowLocalhost,
           urlString.hasPrefix("http://127.0.0.1:") || urlString.hasPrefix("http://localhost:") {
            return
        }
        let allowedPrefixes = [
            "https://github.com/\(repoSlug)/",
            "https://objects.githubusercontent.com/",
            "https://release-assets.githubusercontent.com/"
        ]
        if allowedPrefixes.contains(where: { urlString.hasPrefix($0) }) {
            return
        }
        throw UpdaterError.untrustedURL("Refusing untrusted update URL: \(urlString)")
    }

    nonisolated static func resolvePlatformAsset(
        _ platforms: [String: PlatformAsset]
    ) -> (platformKey: String, asset: PlatformAsset)? {
        #if arch(arm64)
        let candidates = ["darwin-aarch64", "darwin-universal"]
        #elseif arch(x86_64)
        let candidates = ["darwin-x86_64", "darwin-universal"]
        #else
        let candidates = ["darwin-universal"]
        #endif

        for key in candidates {
            if let asset = platforms[key] {
                return (key, asset)
            }
        }
        return nil
    }

    nonisolated static func parseSemver(_ raw: String) -> Semver? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") {
            s.removeFirst()
        }
        if let idx = s.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            s = String(s[..<idx])
        }
        guard !s.isEmpty else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let major = UInt64(parts[0]),
              let minor = UInt64(parts[1]) else {
            return nil
        }
        let patch: UInt64
        if parts.count == 3 {
            guard let p = UInt64(parts[2]) else { return nil }
            patch = p
        } else {
            patch = 0
        }
        return Semver(major: major, minor: minor, patch: patch)
    }

    nonisolated static func inspectAppBundlePath(_ executableURL: URL) -> (appURL: URL?, isWritable: Bool) {
        let resolved = executableURL.resolvingSymlinksInPath()
        let macOSDir = resolved.deletingLastPathComponent()
        let contentsDir = macOSDir.deletingLastPathComponent()
        let appDir = contentsDir.deletingLastPathComponent()

        let isBundleLayout = macOSDir.lastPathComponent == "MacOS"
            && contentsDir.lastPathComponent == "Contents"
            && appDir.lastPathComponent.hasSuffix(".app")
        guard isBundleLayout else {
            return (nil, false)
        }

        let appPath = appDir.path
        if appPath.hasPrefix("/Volumes/") || appPath.contains("AppTranslocation") {
            return (nil, false)
        }

        let parentDir = appDir.deletingLastPathComponent()
        let probePath = parentDir
            .appendingPathComponent(".eave-update-probe-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)")
            .path
        let fd = Darwin.open(probePath, O_CREAT | O_EXCL | O_WRONLY, 0o600)
        if fd >= 0 {
            Darwin.close(fd)
            Darwin.unlink(probePath)
            return (appDir, true)
        }
        return (appDir, false)
    }

    nonisolated static func writeHandoffFile(at url: URL, payload: UpdateHandoffPayload) throws {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)

        let tmpURL = url.deletingPathExtension().appendingPathExtension("json.tmp")
        let fd = Darwin.open(tmpURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw UpdaterError.ioError("Open handoff temp file failed (errno \(errno))")
        }

        var closed = false
        defer {
            if !closed {
                Darwin.close(fd)
            }
        }

        try data.withUnsafeBytes { rawBuf in
            guard let base = rawBuf.baseAddress else { return }
            var remaining = rawBuf.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(fd, base.advanced(by: offset), remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw UpdaterError.ioError("Write handoff temp file failed (errno \(errno))")
                }
                offset += written
                remaining -= written
            }
        }

        guard Darwin.fsync(fd) == 0 else {
            throw UpdaterError.ioError("Sync handoff temp file failed (errno \(errno))")
        }
        Darwin.close(fd)
        closed = true

        guard Darwin.rename(tmpURL.path, url.path) == 0 else {
            try? fm.removeItem(at: tmpURL)
            throw UpdaterError.ioError("Rename handoff file failed (errno \(errno))")
        }
    }

    /// Atomically consumes `update-handoff.json` once on startup.
    /// Renames and removes before returning so a restore bug can never crash-loop.
    nonisolated static func consumeHandoffFile(
        at url: URL,
        nowMs: UInt64 = AutoUpdater.nowEpochMs()
    ) -> UpdateHandoffPayload? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let consumingURL = url.deletingPathExtension().appendingPathExtension("consuming.json")
        guard Darwin.rename(url.path, consumingURL.path) == 0 else {
            try? fm.removeItem(at: url)
            return nil
        }

        let rawData = try? Data(contentsOf: consumingURL)
        try? fm.removeItem(at: consumingURL)

        guard let rawData,
              let parsed = try? JSONDecoder().decode(UpdateHandoffPayload.self, from: rawData) else {
            return nil
        }

        let ageMs = nowMs >= parsed.createdAtMs ? (nowMs - parsed.createdAtMs) : 0
        guard parsed.schemaVersion == 1, ageMs <= parsed.ttlMs else {
            return nil
        }
        return parsed
    }

    nonisolated static func cleanupStaleStaging(in cacheDir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-3600)
        for entry in entries {
            if let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               modified < cutoff {
                try? fm.removeItem(at: entry)
            }
        }
    }

    nonisolated static func extractAndVerifyBundle(
        archiveURL: URL,
        stageDir: URL,
        format: String,
        bundleName: String,
        expectedBundleID: String
    ) throws -> URL {
        let fm = FileManager.default
        let extractDir = stageDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let extractResult: (Int32, String)
        if format == "app-tar-gz" {
            extractResult = try runSubprocess(
                executable: "/usr/bin/tar",
                arguments: ["-xzf", archiveURL.path, "-C", extractDir.path]
            )
        } else {
            extractResult = try runSubprocess(
                executable: "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractDir.path]
            )
        }
        guard extractResult.0 == 0 else {
            throw UpdaterError.bundleInvalid("Extract archive failed: \(extractResult.1)")
        }

        let stagedApp = extractDir.appendingPathComponent(bundleName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: stagedApp.path, isDirectory: &isDir), isDir.boolValue else {
            throw UpdaterError.bundleInvalid("Extracted archive missing \(bundleName)")
        }

        let actualID = Bundle(url: stagedApp)?.bundleIdentifier ?? ""
        guard actualID == expectedBundleID else {
            throw UpdaterError.bundleInvalid(
                "Staged bundle ID mismatch (got '\(actualID)', expected '\(expectedBundleID)')"
            )
        }

        let csResult = try runSubprocess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", stagedApp.path]
        )
        guard csResult.0 == 0 else {
            throw UpdaterError.bundleInvalid("Staged bundle signature verification failed: \(csResult.1)")
        }

        return stagedApp
    }

    nonisolated static let macOSApplyScript: String = #"""
#!/bin/sh
set -eu

OLD_PID="$1"
TARGET_APP="$2"
STAGED_APP="$3"
STAGE_DIR="$4"
EXPECTED_BUNDLE_ID="$5"
LOG_FILE="$STAGE_DIR/apply.log"
exec >>"$LOG_FILE" 2>&1

echo "[updater] start pid=$OLD_PID target=$TARGET_APP"

KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
PRESERVE_ID=""
CUR_AUTH=$(/usr/bin/codesign -dvv "$TARGET_APP" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -n 1 || true)
NEW_SIG_INFO=$(/usr/bin/codesign -dvv "$STAGED_APP" 2>&1 || true)
if [ -n "$CUR_AUTH" ] && printf '%s\n' "$NEW_SIG_INFO" | /usr/bin/grep -q '^Signature=adhoc'; then
  if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | /usr/bin/grep -Fq "\"${CUR_AUTH}\""; then
    PRESERVE_ID="$CUR_AUTH"
  fi
fi

STAGED_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || true)
if [ "$STAGED_ID" != "$EXPECTED_BUNDLE_ID" ]; then
  echo "[updater] bundle id mismatch: got=$STAGED_ID want=$EXPECTED_BUNDLE_ID"
  exit 1
fi

i=0
while /bin/kill -0 "$OLD_PID" 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 150 ]; then
    echo "[updater] timed out waiting for old pid $OLD_PID"
    exit 1
  fi
  /bin/sleep 0.1
done

/usr/bin/xattr -dr com.apple.quarantine "$STAGED_APP" 2>/dev/null || true
if [ -n "$PRESERVE_ID" ]; then
  echo "[updater] preserving local signing identity: $PRESERVE_ID"
  if [ -d "$STAGED_APP/Contents/Frameworks" ]; then
    /usr/bin/find "$STAGED_APP/Contents/Frameworks" -maxdepth 1 -name '*.dylib' -print0 \
      | /usr/bin/xargs -0 -I{} /usr/bin/codesign --force --keychain "$KEYCHAIN" --sign "$PRESERVE_ID" "{}"
  fi
  /usr/bin/codesign --force --deep --keychain "$KEYCHAIN" --sign "$PRESERVE_ID" "$STAGED_APP"
fi
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

PARENT_DIR=$(/usr/bin/dirname "$TARGET_APP")
APP_NAME=$(/usr/bin/basename "$TARGET_APP")
NEW_TMP="$PARENT_DIR/.${APP_NAME}.new.$$"
OLD_TMP="$PARENT_DIR/.${APP_NAME}.old.$$"

/usr/bin/ditto "$STAGED_APP" "$NEW_TMP"

if ! /bin/mv "$TARGET_APP" "$OLD_TMP"; then
  /bin/rm -rf "$NEW_TMP"
  exit 1
fi

if ! /bin/mv "$NEW_TMP" "$TARGET_APP"; then
  /bin/mv "$OLD_TMP" "$TARGET_APP" || true
  /bin/rm -rf "$NEW_TMP"
  exit 1
fi

/bin/rm -rf "$OLD_TMP" "$STAGE_DIR" || true
/usr/bin/open "$TARGET_APP"
"""#

    nonisolated static func spawnDetachedApplyHelper(
        oldPID: pid_t,
        targetApp: URL,
        stagedApp: URL,
        stageDir: URL,
        expectedBundleID: String
    ) throws {
        let scriptURL = stageDir.appendingPathComponent("apply.sh")
        try macOSApplyScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        guard Darwin.chmod(scriptURL.path, 0o700) == 0 else {
            throw UpdaterError.ioError("chmod apply helper failed (errno \(errno))")
        }

        let argvStrings = [
            "/bin/sh",
            scriptURL.path,
            String(oldPID),
            targetApp.path,
            stagedApp.path,
            stageDir.path,
            expectedBundleID
        ]
        var cArgs = argvStrings.map { strdup($0) }
        cArgs.append(nil)
        defer {
            for ptr in cArgs {
                if let ptr { free(ptr) }
            }
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // Place helper in its own process group so it outlives NSApp.terminate(nil).
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
        posix_spawnattr_setpgroup(&attr, 0)

        var childPID: pid_t = 0
        let rc = posix_spawn(&childPID, "/bin/sh", &fileActions, &attr, &cArgs, environ)
        guard rc == 0 else {
            throw UpdaterError.ioError("Spawn apply helper failed (rc \(rc))")
        }
    }

    nonisolated static func nowEpochMs() -> UInt64 {
        UInt64(max(0, Date().timeIntervalSince1970 * 1000))
    }

    private nonisolated static func defaultDataDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("Eave", isDirectory: true)
    }

    private nonisolated static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(expectedBundleID, isDirectory: true)
    }

    private nonisolated static func runSubprocess(
        executable: String,
        arguments: [String]
    ) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderrPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe
        try process.run()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errText = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, errText)
    }
}

// MARK: - Allowlisted Redirect & Streaming SHA-256 Downloader

private final class AllowlistRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    let allowLocalhost: Bool

    init(allowLocalhost: Bool) {
        self.allowLocalhost = allowLocalhost
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let targetURL = request.url?.absoluteString,
           (try? AutoUpdater.validateDownloadURL(targetURL, allowLocalhost: allowLocalhost)) != nil {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

private final class StreamingFileDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let allowLocalhost: Bool
    private let maxBytes: UInt64
    private let expectedSize: UInt64
    private let destinationURL: URL
    private let partURL: URL
    private let onProgress: @Sendable (Int) -> Void

    private let lock = NSLock()
    private var continuation: CheckedContinuation<(String, UInt64), Error>?
    private var hasher = SHA256()
    private var fileDescriptor: Int32 = -1
    private var totalExpected: UInt64
    private var bytesWritten: UInt64 = 0
    private var lastReportedPct: Int = -1
    private var streamError: Error?

    init(
        allowLocalhost: Bool,
        maxBytes: UInt64,
        expectedSize: UInt64,
        destinationURL: URL,
        onProgress: @escaping @Sendable (Int) -> Void
    ) {
        self.allowLocalhost = allowLocalhost
        self.maxBytes = maxBytes
        self.expectedSize = expectedSize
        self.totalExpected = expectedSize
        self.destinationURL = destinationURL
        self.partURL = destinationURL.deletingPathExtension().appendingPathExtension("part")
        self.onProgress = onProgress
    }

    func download(from url: URL, userAgent: String) async throws -> (String, UInt64) {
        let fd = Darwin.open(partURL.path, O_CREAT | O_WRONLY | O_TRUNC, 0o600)
        guard fd >= 0 else {
            throw AutoUpdater.UpdaterError.ioError("Create download file failed (errno \(errno))")
        }
        lock.withLock {
            self.fileDescriptor = fd
        }

        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)

        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let dataTask = session.dataTask(with: req)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.lock.withLock {
                    self.continuation = continuation
                }
                dataTask.resume()
            }
        } onCancel: {
            dataTask.cancel()
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let targetURL = request.url?.absoluteString,
           (try? AutoUpdater.validateDownloadURL(targetURL, allowLocalhost: allowLocalhost)) != nil {
            completionHandler(request)
        } else {
            lock.withLock {
                if streamError == nil {
                    streamError = AutoUpdater.UpdaterError.untrustedURL(
                        "Refusing untrusted redirect URL: \(request.url?.absoluteString ?? "")"
                    )
                }
            }
            completionHandler(nil)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            lock.withLock {
                streamError = AutoUpdater.UpdaterError.httpError("Invalid download HTTP response")
            }
            completionHandler(.cancel)
            return
        }
        guard http.statusCode == 200 else {
            lock.withLock {
                streamError = AutoUpdater.UpdaterError.httpError("Download returned HTTP \(http.statusCode)")
            }
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > 0 {
            lock.withLock {
                totalExpected = UInt64(response.expectedContentLength)
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var pctToReport: Int?
        var shouldCancel = false

        lock.withLock {
            guard streamError == nil, fileDescriptor >= 0 else { return }
            let nextTotal = bytesWritten + UInt64(data.count)
            if nextTotal > maxBytes {
                streamError = AutoUpdater.UpdaterError.verificationFailed("Download exceeds maximum allowed size")
                shouldCancel = true
                return
            }

            let writeErr: Error? = data.withUnsafeBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return nil }
                var remaining = rawBuf.count
                var offset = 0
                while remaining > 0 {
                    let n = Darwin.write(fileDescriptor, base.advanced(by: offset), remaining)
                    if n < 0 {
                        if errno == EINTR { continue }
                        return AutoUpdater.UpdaterError.ioError("Write download file failed (errno \(errno))")
                    }
                    offset += n
                    remaining -= n
                }
                return nil
            }

            if let writeErr {
                streamError = writeErr
                shouldCancel = true
                return
            }

            hasher.update(data: data)
            bytesWritten = nextTotal

            if totalExpected > 0 {
                let pct = Int(min(99, (bytesWritten * 100) / totalExpected))
                if pct != lastReportedPct {
                    lastReportedPct = pct
                    pctToReport = pct
                }
            }
        }

        if shouldCancel {
            dataTask.cancel()
            return
        }
        if let pctToReport {
            onProgress(pctToReport)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }

        let result: Result<(String, UInt64), Error> = lock.withLock {
            let fd = fileDescriptor
            fileDescriptor = -1

            if let err = streamError ?? error {
                if fd >= 0 { Darwin.close(fd) }
                Darwin.unlink(partURL.path)
                return .failure(err)
            }

            guard fd >= 0 else {
                return .failure(AutoUpdater.UpdaterError.ioError("Download file handle unavailable"))
            }

            let syncRC = Darwin.fsync(fd)
            Darwin.close(fd)
            guard syncRC == 0 else {
                Darwin.unlink(partURL.path)
                return .failure(AutoUpdater.UpdaterError.ioError("Sync download file failed (errno \(errno))"))
            }

            guard Darwin.rename(partURL.path, destinationURL.path) == 0 else {
                Darwin.unlink(partURL.path)
                return .failure(AutoUpdater.UpdaterError.ioError("Finalize download file failed (errno \(errno))"))
            }

            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            return .success((digest, bytesWritten))
        }

        let cont = lock.withLock { () -> CheckedContinuation<(String, UInt64), Error>? in
            defer { continuation = nil }
            return continuation
        }
        cont?.resume(with: result)
    }
}
