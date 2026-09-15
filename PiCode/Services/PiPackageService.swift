//
//  PiPackageService.swift
//  PiCode
//
//  Pi packages are Pi's, not PiCode's.
//
//  This service reads the `packages` list out of the settings.json files Pi
//  already owns and shells out to the user's own `pi install` / `pi remove`, so
//  a package installed from this window is installed for the terminal too, and a
//  package removed here is gone from Pi as well. PiCode never writes
//  settings.json itself and never installs anything without an explicit
//  confirmation that names the source, the scope, and the version.
//
//  Browsing reads the public npm registry for packages tagged `pi-package` — the
//  tag the gallery at https://pi.dev/packages documents. That is a read-only
//  network call; the only process started here is Pi's own CLI, with the same
//  login-shell PATH a session gets.
//

import Foundation

enum PiPackageService {

    // MARK: - Scope

    /// Where an install is written. Pi's own `-l` flag is the project scope.
    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case user
        case project

        var id: String { rawValue }

        var label: String {
            switch self {
            case .user: return "This Mac"
            case .project: return "This project"
            }
        }

        var detail: String {
            switch self {
            case .user: return "Pi's user settings (~/.pi/agent/settings.json)"
            case .project: return "The project's .pi/settings.json"
            }
        }
    }

    // MARK: - Models

    /// A package listed in one of Pi's settings files.
    struct InstalledPackage: Identifiable, Equatable, Sendable {
        var source: String
        var scope: Scope

        var id: String { "\(scope.rawValue):\(source)" }

        /// The npm package name a source points at, with any version stripped.
        var npmName: String? { PiPackageService.npmName(from: source) }

        var kindLabel: String {
            if source.hasPrefix("npm:") { return "npm" }
            if source.hasPrefix("git:") || source.contains("://") { return "git" }
            return "local"
        }
    }

    /// One result from the npm registry's `pi-package` search.
    struct GalleryPackage: Identifiable, Equatable, Sendable {
        var name: String
        var summary: String
        var version: String?
        var publisher: String?
        var monthlyDownloads: Int?
        var homepage: URL?
        var repository: URL?

        var id: String { name }
        var source: String { "npm:\(name)" }
        var npmURL: URL? { URL(string: "https://www.npmjs.com/package/\(name)") }
    }

    enum PackageError: LocalizedError {
        case piMissing
        case commandFailed(command: String, output: String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .piMissing:
                return "Pi was not found, so packages cannot be installed or removed."
            case .commandFailed(let command, let output):
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                return detail.isEmpty
                    ? "`pi \(command)` failed."
                    : "`pi \(command)` failed:\n\(detail)"
            case .network(let message):
                return message
            }
        }
    }

    // MARK: - Installed packages

    /// Packages Pi will load, read from the same two settings files Pi reads:
    /// the user file always, and the selected project's file when there is one.
    static func installedPackages(projectPath: String?) -> [InstalledPackage] {
        var rows = sources(in: PiPaths.settingsFile).map {
            InstalledPackage(source: $0, scope: .user)
        }
        if let projectPath {
            rows += sources(in: projectSettingsFile(projectPath: projectPath)).map {
                InstalledPackage(source: $0, scope: .project)
            }
        }
        return rows
    }

    static func projectSettingsFile(projectPath: String) -> URL {
        URL(fileURLWithPath: CanonicalPath.of(projectPath))
            .appendingPathComponent(".pi/settings.json")
    }

    /// The `packages` entries of one settings file. Pi accepts plain strings and
    /// the object form (`{ "source": …, "extensions": […] }`), so both are read.
    static func sources(in settingsURL: URL) -> [String] {
        guard let data = try? Data(contentsOf: settingsURL),
              let root = try? JSONCoding.decode(data),
              let packages = root["packages"]?.arrayValue
        else { return [] }
        return packages.compactMap { entry in
            if let string = entry.stringValue { return string }
            return entry["source"]?.stringValue
        }
    }

    /// `npm:@scope/pkg@1.0.0` → `@scope/pkg`; `npm:pkg@1.0.0` → `pkg`. A package
    /// with no version is returned unchanged, and the leading `@` of a scope is
    /// never mistaken for a version separator.
    static func npmName(from source: String) -> String? {
        guard source.hasPrefix("npm:") else { return nil }
        var name = String(source.dropFirst(4))
        if let separator = name.lastIndex(of: "@"), separator != name.startIndex {
            name = String(name[..<separator])
        }
        return name.isEmpty ? nil : name
    }

    // MARK: - Gallery search

    /// Packages tagged `pi-package` on npm, most relevant first. An empty query
    /// returns the tag's most popular packages, which is the browse list.
    static func search(query: String, size: Int = 30) async throws -> [GalleryPackage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? "keywords:pi-package" : "keywords:pi-package \(trimmed)"
        guard var components = URLComponents(string: "https://registry.npmjs.org/-/v1/search") else {
            throw PackageError.network("Could not build the npm search request.")
        }
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "size", value: String(size))
        ]
        guard let url = components.url else {
            throw PackageError.network("Could not build the npm search request.")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw PackageError.network("npm returned HTTP \(http.statusCode).")
            }
            data = body
        } catch let error as PackageError {
            throw error
        } catch {
            throw PackageError.network("Could not reach the npm registry: \(error.localizedDescription)")
        }

        guard let root = try? JSONCoding.decode(data) else {
            throw PackageError.network("The npm registry sent a response PiCode could not read.")
        }
        return (root["objects"]?.arrayValue ?? []).compactMap { object in
            guard let package = object["package"]?.objectValue,
                  let name = package["name"]?.stringValue
            else { return nil }
            let links = package["links"]?.objectValue
            return GalleryPackage(
                name: name,
                summary: package["description"]?.stringValue ?? "",
                version: package["version"]?.stringValue,
                publisher: package["publisher"]?.objectValue?["username"]?.stringValue
                    ?? package["author"]?.objectValue?["name"]?.stringValue,
                monthlyDownloads: object["downloads"]?.objectValue?["monthly"]?.intValue,
                homepage: links?["homepage"]?.stringValue.flatMap(URL.init(string:)),
                repository: links?["repository"]?.stringValue.flatMap(repositoryURL)
            )
        }
    }

    /// `git+https://github.com/user/repo.git` → `https://github.com/user/repo`.
    private static func repositoryURL(_ raw: String) -> URL? {
        var value = raw
        if value.hasPrefix("git+") { value.removeFirst(4) }
        if value.hasSuffix(".git") { value.removeLast(4) }
        guard value.hasPrefix("http") else { return nil }
        return URL(string: value)
    }

    // MARK: - Install and remove

    @discardableResult
    static func install(source: String,
                        scope: Scope,
                        projectPath: String?,
                        installation: PiInstallation) async throws -> String {
        var arguments = ["install", source]
        if scope == .project { arguments.append("-l") }
        return try await run(arguments, scope: scope, projectPath: projectPath, installation: installation)
    }

    @discardableResult
    static func remove(source: String,
                       scope: Scope,
                       projectPath: String?,
                       installation: PiInstallation) async throws -> String {
        var arguments = ["remove", source]
        if scope == .project { arguments.append("-l") }
        return try await run(arguments, scope: scope, projectPath: projectPath, installation: installation)
    }

    private static func run(_ arguments: [String],
                            scope: Scope,
                            projectPath: String?,
                            installation: PiInstallation) async throws -> String {
        let directory: URL
        switch scope {
        case .user:
            directory = URL(fileURLWithPath: NSHomeDirectory())
        case .project:
            guard let projectPath else { throw PackageError.commandFailed(command: arguments.joined(separator: " "), output: "No project is selected.") }
            directory = URL(fileURLWithPath: CanonicalPath.of(projectPath))
        }

        // Pin Pi's project trust the same way a session does, so a project-scoped
        // install that loads the project's own `.pi` resources reports the trust
        // state the sidebar shows instead of waiting on a prompt the GUI cannot
        // answer.
        var arguments = arguments
        if scope == .project, let projectPath {
            arguments += ProjectTrustService().launchArguments(cwd: projectPath)
        }

        let environment = PiDiscoveryService.launchEnvironment(
            executable: installation.executableURL,
            shellPath: installation.shellPath
        )
        let result = await PiDiscoveryService().run(
            executable: installation.executableURL,
            arguments: arguments,
            directory: directory,
            environment: environment
        )
        let combined = result.stderr.isEmpty
            ? result.stdout
            : result.stdout + (result.stdout.isEmpty ? "" : "\n") + result.stderr
        guard result.exitCode == 0 else {
            throw PackageError.commandFailed(
                command: arguments.joined(separator: " "),
                output: String(ANSIParser.plainText(combined).suffix(1_500))
            )
        }
        return String(ANSIParser.plainText(combined).suffix(1_500))
    }
}
