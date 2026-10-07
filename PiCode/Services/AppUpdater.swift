//
//  AppUpdater.swift
//  PiCode
//
//  Self-update from GitHub Releases. The newest release of `hieunc229/Pie` is
//  titled "Pie {major}.{minor}" and carries the zipped app as an asset. When it is
//  newer than the running build, `state` becomes `.available`; `install()` then
//  downloads the zip, verifies it, and swaps the bundle in place after quitting.
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppUpdater {
    struct Release: Equatable {
        let version: String
        let assetURL: URL
        let assetName: String
        let size: Int64
        /// Lowercase hex SHA-256 from the GitHub API (`sha256:` prefix removed), when present.
        let sha256: String?
    }

    enum State: Equatable {
        case idle
        case available(Release)
        case downloading(Release, progress: Double)
        case installing(Release)
        case failed(Release, message: String)
    }

    private(set) var state: State = .idle

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/hieunc229/Pie/releases/latest")!
    private let checkInterval: Duration = .seconds(6 * 3600)
    private var checkTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?

    /// The release the button should act on, whatever phase it is in.
    var release: Release? {
        switch state {
        case .idle: nil
        case .available(let r), .downloading(let r, _), .installing(let r), .failed(let r, _): r
        }
    }

    var isBusy: Bool {
        switch state {
        case .downloading, .installing: true
        default: false
        }
    }

    // MARK: - Checking

    /// Checks now, then every few hours while the app runs.
    func startChecking() {
        #if DEBUG
        return
        #else
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check()
                try? await Task.sleep(for: self?.checkInterval ?? .seconds(6 * 3600))
            }
        }
        #endif
    }

    func check() async {
        guard !isBusy else { return }
        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !payload.draft, !payload.prerelease,
                  let version = Self.version(in: payload.tagName) ?? Self.version(in: payload.name ?? ""),
                  Self.isNewer(version, than: Self.currentVersion),
                  let asset = payload.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }),
                  let url = URL(string: asset.browserDownloadURL)
            else {
                if case .available = state { state = .idle }
                return
            }
            let release = Release(
                version: version,
                assetURL: url,
                assetName: asset.name,
                size: asset.size,
                sha256: asset.digest?.replacingOccurrences(of: "sha256:", with: "").lowercased()
            )
            if state != .available(release) { state = .available(release) }
        } catch {
            // Offline or rate-limited: try again at the next interval.
        }
    }

    // MARK: - Installing

    func install() {
        guard installTask == nil else { return }
        let release: Release
        switch state {
        case .available(let r), .failed(let r, _): release = r
        default: return
        }
        installTask = Task { [weak self] in
            await self?.run(release)
            self?.installTask = nil
        }
    }

    private func run(_ release: Release) async {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiCodeUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")

            state = .downloading(release, progress: 0)
            try await download(release, to: zip)

            state = .installing(release)
            let destination = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
                throw UpdateError("No write access to \(destination.deletingLastPathComponent().path).")
            }
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
            try await Self.shell("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])

            guard let newApp = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
            else { throw UpdateError("The download contains no app.") }

            guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw UpdateError("The download is a different app.")
            }
            try await Self.shell("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
            // Downloaded by us, but be explicit so Gatekeeper never prompts on relaunch.
            _ = try? await Self.shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            try launchSwapScript(newApp: newApp, destination: destination, work: work)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed(release, message: error.localizedDescription)
        }
    }

    private func download(_ release: Release, to file: URL) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: release.assetURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError("Download failed.")
        }
        let total = response.expectedContentLength > 0 ? response.expectedContentLength : release.size
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var received: Int64 = 0
        var lastReported = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let progress = total > 0 ? min(Double(received) / Double(total), 1) : 0
                if progress - lastReported >= 0.01 {
                    lastReported = progress
                    state = .downloading(release, progress: progress)
                }
            }
        }
        if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
        try handle.close()

        if let expected = release.sha256, expected.count == 64 {
            let actual = try await Self.shell("/usr/bin/shasum", ["-a", "256", file.path])
                .split(separator: " ").first.map(String.init)
            guard actual == expected else { throw UpdateError("Checksum mismatch.") }
        }
    }

    /// Waits for this process to exit, swaps the bundle, and reopens it. Runs detached
    /// so it outlives the app.
    private func launchSwapScript(newApp: URL, destination: URL, work: URL) throws {
        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        BACKUP="$DEST.old"
        rm -rf "$BACKUP"
        mv "$DEST" "$BACKUP" || exit 1
        if /usr/bin/ditto "$NEW" "$DEST"; then
            rm -rf "$BACKUP"
        else
            rm -rf "$DEST"; mv "$BACKUP" "$DEST"
        fi
        /usr/bin/open "$DEST"
        rm -rf "$WORK"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier),
                             newApp.path, destination.path, work.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    // MARK: - Helpers

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let size: Int64
            let browserDownloadURL: String
            let digest: String?
            enum CodingKeys: String, CodingKey {
                case name, size, digest
                case browserDownloadURL = "browser_download_url"
            }
        }
        let tagName: String
        let name: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case name, draft, prerelease, assets
            case tagName = "tag_name"
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// "Pie 1.3", "v1.3" and "1.3.0" all yield their dotted number.
    nonisolated static func version(in text: String) -> String? {
        text.range(of: #"\d+(\.\d+)*"#, options: .regularExpression).map { String(text[$0]) }
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @discardableResult
    nonisolated private static func shell(_ path: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                    let output = out.fileHandleForReading.readDataToEndOfFile()
                    let errors = err.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: String(decoding: output, as: UTF8.self))
                    } else {
                        let message = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: UpdateError(message.isEmpty ? "\(path) failed." : message))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
