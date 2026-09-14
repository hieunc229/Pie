//
//  TrustViews.swift
//  PiCode
//
//  Project trust UI. PiCode shows exactly what Pi will and will not load, and
//  writes decisions only through Pi's own trust store (`~/.pi/agent/trust.json`),
//  which is also what Pi's `/trust` command writes.
//

import SwiftUI

struct ProjectTrustPrompt: View {
    @Bindable var controller: PiSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("This project can change how Pi behaves", systemImage: "lock.shield")
                .font(.callout.weight(.semibold))

            Text("\(controller.projectPath.abbreviatingHomeDirectory) contains project resources Pi can load: settings, extensions, skills, prompts, themes, or system prompts. Pi will not load them unless you trust this project.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Trust & Remember") {
                    controller.setTrust(true, remember: true)
                }
                .buttonStyle(.borderedProminent)

                Button("Trust for This Session") {
                    controller.setTrust(true, remember: false)
                }

                Button("Don't Trust") {
                    controller.setTrust(false, remember: false)
                }

                Spacer(minLength: 0)

                Button("Trust Parent Folder Instead") {
                    controller.trustParentFolder()
                }
                .help("Writes a trust decision for the parent directory, which Pi applies to this project by nearest-ancestor lookup.")
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.orange.opacity(0.4))
        )
    }
}

struct UntrustedProjectNotice: View {
    @Bindable var controller: PiSessionController

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .foregroundStyle(.secondary)
            Text("Project resources are not trusted, so Pi is running without them.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Trust…") {
                controller.setTrust(true, remember: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Compact trust indicator shown in the composer's context row.
struct TrustBadge: View {
    var state: ProjectTrustState

    var body: some View {
        switch state {
        case .trusted:
            StatusPill(text: "Trusted", systemImage: "lock.open", tint: .green)
        case .notRequired:
            StatusPill(text: "No project resources", systemImage: "lock", tint: .secondary)
        case .asked:
            StatusPill(text: "Trust needed", systemImage: "lock.trianglebadge.exclamationmark", tint: .orange, isProminent: true)
        case .untrusted:
            StatusPill(text: "Not trusted", systemImage: "lock", tint: .orange)
        case .unknown:
            StatusPill(text: "Trust unknown", systemImage: "lock", tint: .secondary)
        }
    }
}

/// The composer's access control: one icon beside the paperclip that says what
/// Pi is allowed to load, and a popover that explains the part people get wrong
/// — Pi always runs with the user's own permissions, so this decision is about
/// *project resources*, not about sandboxing the agent.
struct ComposerAccessControl: View {
    @Bindable var controller: PiSessionController
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover = true
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12.5))
                .foregroundStyle(tint)
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Access: \(shortLabel)")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) { popover }
    }

    private var popover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)

            Text("Pi runs as you — the current macOS user — so it can read and write the files your account can, and run shell commands with your permissions. Trusting a project does not change any of that: it only decides whether Pi loads that project's own settings, extensions, skills, prompts, themes, and system prompts.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340, alignment: .leading)

            if let detail = stateDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 340, alignment: .leading)
            }

            HStack(spacing: 8) {
                Button("Trust & Remember") { decide(true, remember: true) }
                    .buttonStyle(.borderedProminent)
                Button("This Session") { decide(true, remember: false) }
                Button("Don't Trust") { decide(false, remember: false) }
            }

            Text("Changing this restarts Pi for this session. Decisions are written to Pi's own trust store, the same file `/trust` writes.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340, alignment: .leading)
        }
        .padding(14)
    }

    private func decide(_ trusted: Bool, remember: Bool) {
        isShowingPopover = false
        controller.setTrust(trusted, remember: remember)
    }

    private var title: String {
        switch controller.trustState {
        case .trusted: return "This project is trusted"
        case .notRequired: return "This project has nothing to load"
        case .asked: return "Waiting for your decision"
        case .untrusted: return "This project is not trusted"
        case .unknown: return "Trust state unknown"
        }
    }

    private var shortLabel: String {
        switch controller.trustState {
        case .trusted: return "trusted"
        case .notRequired: return "no project resources"
        case .asked: return "waiting for you"
        case .untrusted: return "not trusted"
        case .unknown: return "unknown"
        }
    }

    private var symbol: String {
        switch controller.trustState {
        case .trusted: return "lock.open"
        case .notRequired: return "lock"
        case .asked: return "lock.trianglebadge.exclamationmark"
        case .untrusted: return "lock"
        case .unknown: return "lock"
        }
    }

    private var tint: Color {
        switch controller.trustState {
        case .trusted: return .green
        case .asked, .untrusted: return .orange
        case .notRequired, .unknown: return .secondary
        }
    }

    private var stateDetail: String? {
        switch controller.trustState {
        case .trusted, .notRequired, .unknown:
            return nil
        case .asked:
            return "PiCode asked Pi for the resources this project declares and has not had an answer yet."
        case .untrusted:
            return "Pi is running with `--no-approve`, so this project's resources are ignored."
        }
    }
}
