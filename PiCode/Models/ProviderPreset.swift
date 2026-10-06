//
//  ProviderPreset.swift
//  PiCode
//
//  Starting points for third-party providers. A preset fills the endpoint,
//  protocol, and a few model ids so a common provider is two clicks instead of a
//  documentation lookup; every field stays editable, and "Custom" fills nothing.
//
//  The model ids are only a convenience: "Load Models" queries the endpoint for
//  the real list, and editing the field replaces them.
//

import Foundation

struct ProviderPreset: Identifiable, Hashable {
    var id: String
    var name: String
    var providerID: String
    var baseURL: String
    var api: String
    var modelIDs: [String]
    var keyPlaceholder: String
    /// Shown under the picker when the preset has a caveat worth reading.
    var note: String?

    var isCustom: Bool { id == "custom" }
}

enum ProviderPresets {
    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "custom",
            name: "Custom",
            providerID: "",
            baseURL: "",
            api: PiProviderService.supportedAPIs[0],
            modelIDs: [],
            keyPlaceholder: "$MY_API_KEY or sk-…",
            note: "Enter the endpoint, protocol, credentials, and model ids yourself."
        ),
        ProviderPreset(
            id: "openai",
            name: "OpenAI",
            providerID: "openai",
            baseURL: "https://api.openai.com/v1",
            api: "openai-completions",
            modelIDs: ["gpt-5", "gpt-5-mini", "o3"],
            keyPlaceholder: "sk-…",
            note: nil
        ),
        ProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            providerID: "openrouter",
            baseURL: "https://openrouter.ai/api/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "$OPENROUTER_API_KEY or sk-or-…",
            note: "One key, many models. Use Load Models to pull the catalog."
        ),
        ProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            providerID: "deepseek",
            baseURL: "https://api.deepseek.com/v1",
            api: "openai-completions",
            modelIDs: ["deepseek-chat", "deepseek-reasoner"],
            keyPlaceholder: "sk-…",
            note: nil
        ),
        ProviderPreset(
            id: "anthropic",
            name: "Anthropic",
            providerID: "anthropic",
            baseURL: "https://api.anthropic.com",
            api: "anthropic-messages",
            modelIDs: [],
            keyPlaceholder: "sk-ant-…",
            note: "Anthropic exposes no model-list endpoint, so add model ids by hand."
        ),
        ProviderPreset(
            id: "google",
            name: "Google Gemini",
            providerID: "google",
            baseURL: "https://generativelanguage.googleapis.com",
            api: "google-generative-ai",
            modelIDs: [],
            keyPlaceholder: "AIza…",
            note: nil
        ),
        ProviderPreset(
            id: "xai",
            name: "xAI Grok",
            providerID: "xai",
            baseURL: "https://api.x.ai/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "xai-…",
            note: nil
        ),
        ProviderPreset(
            id: "groq",
            name: "Groq",
            providerID: "groq",
            baseURL: "https://api.groq.com/openai/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "gsk_…",
            note: nil
        ),
        ProviderPreset(
            id: "mistral",
            name: "Mistral",
            providerID: "mistral",
            baseURL: "https://api.mistral.ai/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "$MISTRAL_API_KEY",
            note: nil
        ),
        ProviderPreset(
            id: "together",
            name: "Together AI",
            providerID: "together",
            baseURL: "https://api.together.xyz/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "$TOGETHER_API_KEY",
            note: nil
        ),
        ProviderPreset(
            id: "fireworks",
            name: "Fireworks AI",
            providerID: "fireworks",
            baseURL: "https://api.fireworks.ai/inference/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "$FIREWORKS_API_KEY",
            note: nil
        ),
        ProviderPreset(
            id: "ollama",
            name: "Ollama (local)",
            providerID: "ollama",
            baseURL: "http://localhost:11434/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "no-key-required",
            note: "Local server. Leave the key as-is."
        ),
        ProviderPreset(
            id: "lmstudio",
            name: "LM Studio (local)",
            providerID: "lmstudio",
            baseURL: "http://localhost:1234/v1",
            api: "openai-completions",
            modelIDs: [],
            keyPlaceholder: "no-key-required",
            note: "Local server. Leave the key as-is."
        )
    ]

    static func preset(id: String) -> ProviderPreset {
        all.first { $0.id == id } ?? all[0]
    }

    /// The preset whose endpoint matches, so editing an existing provider shows
    /// where it came from. `nil` when it does not match any preset.
    static func matching(baseURL: String?, providerID: String) -> ProviderPreset? {
        guard let baseURL, !baseURL.isEmpty else { return nil }
        return all.first { !$0.isCustom && $0.baseURL == baseURL && $0.providerID == providerID }
            ?? all.first { !$0.isCustom && $0.baseURL == baseURL }
    }
}
