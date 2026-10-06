//
//  ComposerModelPickerSupport.swift
//  PiCode
//
//  Small presentation types and sizing rules for the composer's drill-down
//  picker. Keeping these outside the view makes the layout policy explicit.
//

import CoreGraphics
import Foundation

enum ComposerModelPickerLevel: Equatable {
    case root
    case harness
    case provider
    case model
}

enum ComposerModelPickerLayout {
    static let width: CGFloat = 380
    static let maximumHeight: CGFloat = 420

    static func height(for level: ComposerModelPickerLevel,
                       harnessCount: Int,
                       providerCount: Int,
                       reasoningCount: Int,
                       modelCount: Int,
                       modelGroupCount: Int) -> CGFloat {
        let height: CGFloat

        switch level {
        case .root:
            height = reasoningCount > 0 ? 202 : 174
        case .harness:
            // Header + rows (which carry subtitles) + the explanatory footer.
            height = 44 + CGFloat(max(harnessCount, 1)) * 47 + 68
        case .provider:
            height = 44 + CGFloat(max(providerCount, 1)) * 35
        case .model:
            // Header, search field, provider section headers, and model rows.
            height = 82
                + CGFloat(modelGroupCount) * 26
                + CGFloat(max(modelCount, 1)) * 35
        }

        return min(maximumHeight, max(height, 114))
    }
}

extension String {
    /// Turns catalog identifiers into menu labels without damaging brand names
    /// which already contain intentional capitalization.
    var pickerCapitalized: String {
        let brands = [
            "openai": "OpenAI",
            "openrouter": "OpenRouter",
            "deepseek": "DeepSeek",
            "xai": "xAI",
            "lmstudio": "LM Studio"
        ]
        if let brand = brands[lowercased()] { return brand }
        guard self == lowercased() else { return self }
        return split(separator: "-", omittingEmptySubsequences: false)
            .map { String($0).localizedCapitalized }
            .joined(separator: " ")
    }
}
