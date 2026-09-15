//
//  PackagesModel.swift
//  PiCode
//
//  State for the package browser. It holds the gallery results, the packages Pi
//  reports as installed, and the one operation (install or remove) currently in
//  flight. Nothing here writes Pi's settings itself: every mutation goes through
//  `PiPackageService`, which hands the work to Pi's own CLI.
//

import Foundation
import Observation

@Observable
@MainActor
final class PackagesModel {
    /// The search field's contents. Empty shows the tag's most popular packages.
    var query = ""

    private(set) var results: [PiPackageService.GalleryPackage] = []
    private(set) var installed: [PiPackageService.InstalledPackage] = []
    private(set) var isSearching = false
    /// Sources with an install or remove running, so a row can show a spinner and
    /// a second click cannot start the same work twice.
    private(set) var busySources: Set<String> = []

    var lastError: String?
    var statusMessage: String?

    private var searchTask: Task<Void, Never>?

    // MARK: - Derived

    /// npm names already present in a settings file, whatever their version.
    var installedNPMNames: Set<String> {
        Set(installed.compactMap(\.npmName))
    }

    func isInstalled(named name: String) -> Bool {
        installedNPMNames.contains(name)
    }

    func isBusy(_ source: String) -> Bool {
        busySources.contains(source)
    }

    // MARK: - Loading

    func reloadInstalled(projectPath: String?) {
        installed = PiPackageService.installedPackages(projectPath: projectPath)
    }

    /// Debounced so typing does not fire a request per keystroke.
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    func performSearch() async {
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await PiPackageService.search(query: query)
            // A newer query may have started while this one was in flight.
            guard !Task.isCancelled else { return }
            results = found
            lastError = nil
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mutations

    func install(source: String,
                 scope: PiPackageService.Scope,
                 projectPath: String?,
                 installation: PiInstallation?) async {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let installation else {
            lastError = PiPackageService.PackageError.piMissing.localizedDescription
            return
        }

        busySources.insert(trimmed)
        lastError = nil
        statusMessage = nil
        defer { busySources.remove(trimmed) }

        do {
            _ = try await PiPackageService.install(
                source: trimmed,
                scope: scope,
                projectPath: projectPath,
                installation: installation
            )
            reloadInstalled(projectPath: projectPath)
            statusMessage = "Installed \(trimmed). Restart a session to load its extensions."
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove(_ package: PiPackageService.InstalledPackage,
                projectPath: String?,
                installation: PiInstallation?) async {
        guard let installation else {
            lastError = PiPackageService.PackageError.piMissing.localizedDescription
            return
        }

        busySources.insert(package.source)
        lastError = nil
        statusMessage = nil
        defer { busySources.remove(package.source) }

        do {
            _ = try await PiPackageService.remove(
                source: package.source,
                scope: package.scope,
                projectPath: projectPath,
                installation: installation
            )
            reloadInstalled(projectPath: projectPath)
            statusMessage = "Removed \(package.source)."
        } catch {
            lastError = error.localizedDescription
        }
    }
}
