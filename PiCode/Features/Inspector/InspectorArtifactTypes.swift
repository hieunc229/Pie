//
//  InspectorArtifactTypes.swift
//  PiCode
//
//  Presentation types used by the full-bleed artifact renderers in the right
//  panel. The transcript remains responsible for its own compact cards.
//

import SwiftUI

enum InspectorToolContent {
    case terminal(command: String?, output: String?)
    case code(text: String, language: SyntaxLanguage)
    case diff(String)
    case generic(arguments: String?, output: String?, details: String?)
    case running
    case empty(message: String, isFailure: Bool)
}

struct GitDiffLine: Identifiable {
    enum Kind {
        case metadata
        case hunk
        case context
        case addition
        case deletion
    }

    let id: Int
    let kind: Kind
    let text: String
    let oldLine: Int?
    let newLine: Int?

    var marker: String {
        switch kind {
        case .addition: return "+"
        case .deletion: return "−"
        default: return ""
        }
    }

    var foreground: Color {
        switch kind {
        case .metadata: return .secondary
        case .hunk: return .accentColor
        default: return .primary
        }
    }

    var markerColor: Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        default: return .clear
        }
    }

    var background: Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        case .hunk: return Color.accentColor.opacity(0.09)
        case .metadata: return Color.primary.opacity(0.025)
        case .context: return .clear
        }
    }

    var gutterBackground: Color {
        switch kind {
        case .addition: return Color.green.opacity(0.09)
        case .deletion: return Color.red.opacity(0.09)
        case .hunk: return Color.accentColor.opacity(0.06)
        default: return Color.primary.opacity(0.025)
        }
    }
}
