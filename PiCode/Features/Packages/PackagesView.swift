//
//  PackagesView.swift
//  PiCode
//
//  The package browser: what Pi will load, and what the `pi-package` tag on npm
//  offers. It is a read-only view of npm plus two buttons that hand work to Pi's
//  own CLI, so a package installed here is a package the terminal has too.
//
//  The page is a detail-column surface like a session is: its own header sits in
//  the window's titlebar band, and the content scrolls under it in the same
//  column the transcript uses. Selecting a chat in the sidebar (or New chat)
//  leaves the page and opens that session.
//

import SwiftUI

struct PackagesView: View {
    @Bindable var state: AppState
    /// Whether the sidebar is showing, so the header clears the traffic lights
    /// when it is not — the same rule `ContentHeader` follows.
    var isSidebarVisible: Bool

    @State private var model = PackagesModel()
    @State private var pendingInstall: PiPackageService.GalleryPackage?
    @State private var pendingRemoval: PiPackageService.InstalledPackage?
    @State private var isInstallingCustom = false

    private var backdrop: Color { AppTheme.background }

    var body: some View {
        ScrollView {
            ConversationColumn {
                VStack(alignment: .leading, spacing: 22) {
                    searchRow
                    securityNote
                    installedSection
                    browseSection
                    statusArea
                }
                .padding(.top, 26)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity)
        }
        .background(backdrop)
        .overlay(alignment: .top) {
            header.ignoresSafeArea(.container, edges: .top)
        }
        .task {
            model.reloadInstalled(projectPath: state.selectedProjectPath)
            await model.performSearch()
        }
        .onChange(of: model.query) { _, _ in model.scheduleSearch() }
        .onChange(of: state.selectedProjectPath) { _, path in
            model.reloadInstalled(projectPath: path)
        }
        .sheet(item: $pendingInstall) { package in
            InstallPackageSheet(
                model: model,
                installation: state.installation,
                projectPath: state.selectedProjectPath,
                package: package
            )
        }
        .sheet(isPresented: $isInstallingCustom) {
            InstallPackageSheet(
                model: model,
                installation: state.installation,
                projectPath: state.selectedProjectPath,
                package: nil
            )
        }
        .confirmationDialog(
            "Remove this package?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let package = pendingRemoval {
                Button("Remove", role: .destructive) {
                    pendingRemoval = nil
                    Task {
                        await model.remove(
                            package,
                            projectPath: state.selectedProjectPath,
                            installation: state.installation
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            if let package = pendingRemoval {
                Text("PiCode asks Pi to remove `\(package.source)` from \(package.scope.detail). Pi and the terminal lose it too.")
            }
        }
    }

    // MARK: - Header

    /// The page's own header, drawn in the titlebar band the way the transcript's
    /// header is, so switching between a session and this page does not move the
    /// first line down.
    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox")
                    .font(.system(size: Typography.baseSize))
                    .foregroundStyle(.tertiary)
                Text("Packages")
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                model.reloadInstalled(projectPath: state.selectedProjectPath)
                Task { await model.performSearch() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .imageScale(.medium)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Reload installed packages and refresh the gallery")
            .accessibilityLabel("Reload packages")
        }
        .padding(.leading, ContentHeaderMetrics.leadingInset(isSidebarVisible: isSidebarVisible))
        .padding(.trailing, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(backdrop)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    // MARK: - Search

    private var searchRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search pi packages", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                if model.isSearching {
                    ProgressView().controlSize(.small)
                } else if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Button("Install from Source…") { isInstallingCustom = true }
                .help("Install an npm package, a git repository, or a local path through Pi")
        }
    }

    // MARK: - Security note

    /// The warning Pi's own documentation opens with. It is not dismissible: a
    /// package can run arbitrary code with the user's full account access, and
    /// the page that installs them is the only place that has to say so.
    private var securityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Pi packages run with full access")
                    .font(Typography.bodySemibold)
                Text("Extensions execute arbitrary code and skills can instruct the model to run commands. Review the source before installing. Browsing shows packages tagged `pi-package` on the public npm registry; PiCode hands installs and removals to your own `pi` binary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Link("pi.dev/packages", destination: URL(string: "https://pi.dev/packages") ?? URL(string: "https://pi.dev")!)
                .font(.caption)
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.28))
        )
    }

    // MARK: - Installed

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(
                "Installed",
                subtitle: model.installed.isEmpty
                    ? "Nothing installed yet"
                    : "\(model.installed.count) package\(model.installed.count == 1 ? "" : "s") Pi will load"
            )

            if model.installed.isEmpty {
                emptyRow("No packages installed yet. Install one from the gallery below.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.installed.enumerated()), id: \.element.id) { index, package in
                        if index > 0 { Divider() }
                        InstalledPackageRow(
                            package: package,
                            isBusy: model.isBusy(package.source)
                        ) {
                            pendingRemoval = package
                        }
                    }
                }
                .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor))
                )
            }
        }
    }

    // MARK: - Browse

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(
                "Browse",
                subtitle: model.query.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Popular packages tagged pi-package on npm"
                    : "npm results for “\(model.query)”"
            )

            if model.results.isEmpty {
                if model.isSearching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching npm…")
                            .font(Typography.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                } else {
                    emptyRow("No packages found.")
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(model.results) { package in
                        GalleryPackageCard(
                            package: package,
                            isInstalled: model.isInstalled(named: package.name),
                            isBusy: model.isBusy(package.source)
                        ) {
                            pendingInstall = package
                        }
                    }
                }
            }
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusArea: some View {
        if let status = model.statusMessage {
            Label(status, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let error = model.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(Typography.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Installed row

private struct InstalledPackageRow: View {
    var package: PiPackageService.InstalledPackage
    var isBusy: Bool
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tertiary)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(package.source)
                    .font(Typography.bodySemibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(package.scope.label) · \(package.kindLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                Button("Remove") { onRemove() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var icon: String {
        switch package.kindLabel {
        case "npm": return "shippingbox"
        case "git": return "arrow.triangle.branch"
        default: return "folder"
        }
    }
}

// MARK: - Gallery card

private struct GalleryPackageCard: View {
    var package: PiPackageService.GalleryPackage
    var isInstalled: Bool
    var isBusy: Bool
    var onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(package.name)
                    .font(Typography.bodySemibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let version = package.version {
                    Text(version)
                        .font(Typography.codeBlock)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                installControl
            }

            if !package.summary.isEmpty {
                Text(package.summary)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if let publisher = package.publisher {
                    Label(publisher, systemImage: "person")
                }
                if let downloads = package.monthlyDownloads {
                    Label("\(Format.tokens(downloads))/mo", systemImage: "arrow.down.circle")
                }
                if let repository = package.repository {
                    Link(destination: repository) {
                        Label("repo", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }
                if let homepage = package.homepage {
                    Link(destination: homepage) {
                        Label("site", systemImage: "safari")
                    }
                }
                if let npm = package.npmURL {
                    Link(destination: npm) {
                        Label("npm", systemImage: "shippingbox")
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(12)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    @ViewBuilder
    private var installControl: some View {
        if isBusy {
            ProgressView().controlSize(.small)
        } else if isInstalled {
            StatusPill(text: "Installed", systemImage: "checkmark", tint: .green)
        } else {
            Button("Install") { onInstall() }
                .controlSize(.small)
        }
    }
}

// MARK: - Install sheet

/// Confirms one install. A gallery package arrives with its source and version
/// fixed; a manual source is typed here. Either way the sheet names the source,
/// the scope, and — when npm knows it — the version before anything runs, which
/// is the rule the README sets for installing executable code.
private struct InstallPackageSheet: View {
    @Bindable var model: PackagesModel
    var installation: PiInstallation?
    var projectPath: String?
    /// `nil` means the source is typed here rather than taken from the gallery.
    var package: PiPackageService.GalleryPackage?

    @State private var source = ""
    @State private var scope: PiPackageService.Scope = .user
    @State private var isInstalling = false
    @Environment(\.dismiss) private var dismiss

    private var effectiveSource: String {
        package?.source ?? source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(package == nil ? "Install a Pi package" : "Install \(package?.name ?? "")")
                .font(.headline)

            if let package {
                LabeledContent("Source", value: package.source)
                if let version = package.version {
                    LabeledContent("Version", value: version)
                }
                if !package.summary.isEmpty {
                    Text(package.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                TextField("Source", text: $source, prompt: Text("npm:@scope/pkg, git:github.com/user/repo, or /path/to/package"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                Text("The same sources `pi install` accepts: an npm package, a git repository, or a local path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Install for", selection: $scope) {
                ForEach(PiPackageService.Scope.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if scope == .project && projectPath == nil {
                Text("No project is selected, so a project-scoped install has nowhere to go.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            securityNote

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isInstalling {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Cancel") { dismiss() }
                    .disabled(isInstalling)
                Button("Install") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canInstall)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if source.isEmpty, let package { source = package.source }
        }
    }

    private var canInstall: Bool {
        guard !isInstalling, !effectiveSource.isEmpty else { return false }
        return scope == .user || projectPath != nil
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("This package will run with full access to your account. Extensions execute arbitrary code and skills can instruct the model to run commands. Install only what you trust.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func install() {
        isInstalling = true
        Task {
            await model.install(
                source: effectiveSource,
                scope: scope,
                projectPath: projectPath,
                installation: installation
            )
            isInstalling = false
            if model.lastError == nil { dismiss() }
        }
    }
}
