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
