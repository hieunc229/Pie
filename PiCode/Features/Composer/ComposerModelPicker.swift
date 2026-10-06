//
//  ComposerModelPicker.swift
//  PiCode
//
//  The composer's model control: a drill-down menu for Harness, Provider, and
//  Model, with a stepped reasoning control for the selected model.
//
//  Harness is not a per-chat setting: each runtime is its own process with its
//  own session store, so switching harness cannot carry the current conversation
//  across. Choosing another harness therefore starts a new chat on it, and the
//  current chat stays where it is.
//

import SwiftUI

struct ComposerModelPicker: View {
    @Bindable var controller: PiSessionController
    @Bindable var state: AppState
    var onDismiss: () -> Void

    @State private var level: ComposerModelPickerLevel = .root
    @State private var outgoingLevel: ComposerModelPickerLevel?
    @State private var slideDirection: CGFloat = 1
    @State private var slideProgress: CGFloat = 1
    @State private var animationGeneration = 0
    /// The provider chosen on the provider level; scopes the model list.
    @State private var providerFilter: String?
    @State private var query = ""

    var body: some View {
        ZStack(alignment: .top) {
            if let outgoingLevel {
                content(for: outgoingLevel)
                    .offset(x: -slideDirection * ComposerModelPickerLayout.width * slideProgress)
                    .allowsHitTesting(false)
            }

            content(for: level)
                .offset(x: slideDirection * ComposerModelPickerLayout.width * (1 - slideProgress))
        }
        .frame(width: ComposerModelPickerLayout.width,
               height: fittedHeight,
               alignment: .top)
        .clipped()
        .allowsHitTesting(outgoingLevel == nil)
        .animation(.easeInOut(duration: 0.2), value: fittedHeight)
        .task { await controller.refreshModels() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for level: ComposerModelPickerLevel) -> some View {
        switch level {
        case .root: rootList
        case .harness: submenu(title: "Harness") { harnessList }
        case .provider: submenu(title: "Provider") { providerList }
        case .model: submenu(title: providerFilter?.pickerCapitalized ?? "Model") { modelList }
        }
    }

    private func submenu<Body: View>(title: String, @ViewBuilder body: () -> Body) -> some View {
        VStack(spacing: 0) {
            backRow(title: title)
            Divider()
            body()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var rootList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pickerRow(title: "Harness",
                          value: controller.harness.displayName,
                          systemImage: "shippingbox") {
                    navigate(to: .harness)
                }

                pickerRow(title: "Provider",
                          value: currentProvider?.pickerCapitalized ?? "Any",
                          systemImage: "building.2") {
                    providerFilter = nil
                    navigate(to: .provider)
                }

                pickerRow(title: "Model",
                          value: controller.model?.displayName ?? "Default",
                          systemImage: "cpu") {
                    providerFilter = currentProvider
                    navigate(to: .model)
                }

                ComposerReasoningSlider(
                    levels: controller.thinkingLevels,
                    selectedLevel: controller.thinkingLevel,
                    onSelect: { level in
                        Task { await controller.setThinkingLevel(level) }
                    }
                )
            }
            .padding(.vertical, 4)
        }
    }

    private var harnessList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.harnesses.usableHarnesses) { descriptor in
                    let isCurrent = descriptor.id == controller.harness.id
                    selectionRow(
                        title: descriptor.displayName,
                        subtitle: isCurrent ? "Current chat" : "Start a new chat on \(descriptor.displayName)",
                        isSelected: isCurrent
                    ) {
                        selectHarness(descriptor)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .safeAreaInset(edge: .bottom) {
            footnote("A harness is fixed for a chat. Choosing another starts a new chat on it; this conversation stays on \(controller.harness.displayName).")
        }
    }

    private var providerList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if providers.isEmpty {
                    if let error = controller.modelCatalogError {
                        note("\(controller.harness.displayName) could not load its models: \(error)")
                    } else {
                        note("\(controller.harness.displayName) did not return any providers. Configure one in Settings → Providers, then reopen this menu.")
                    }
                } else {
                    ForEach(providers, id: \.self) { provider in
                        selectionRow(
                            title: provider.pickerCapitalized,
                            subtitle: nil,
                            isSelected: provider == currentProvider
                        ) {
                            providerFilter = provider
                            navigate(to: .model)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var modelList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                TextField("Search models", text: $query)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if filteredModels.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "No models available" : "No matching models",
                            systemImage: "magnifyingglass",
                            description: Text(emptyDescription)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(modelGroups, id: \.provider) { group in
                            Section {
                                ForEach(group.models) { model in
                                    selectionRow(
                                        title: model.displayName,
                                        subtitle: model.displayName == model.id ? nil : model.id,
                                        isSelected: isSelected(model),
                                        trailing: modelBadges(model)
                                    ) {
                                        selectModel(model)
                                    }
                                }
                            } header: {
                                Text(group.provider.pickerCapitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(.bar)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func backRow(title: String) -> some View {
        Button { goBack() } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text("Back")
                Spacer(minLength: 0)
                Text(title)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private func pickerRow(title: String,
                           value: String,
                           systemImage: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func selectionRow(title: String,
                              subtitle: String?,
                              isSelected: Bool,
                              trailing: AnyView? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(!isSelected)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let trailing { trailing }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func modelBadges(_ model: PiModel) -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                if model.reasoning {
                    Image(systemName: "brain").foregroundStyle(.tertiary)
                }
                if model.supportsImages {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
        )
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func navigate(to destination: ComposerModelPickerLevel, goingBack: Bool = false) {
        guard destination != level, outgoingLevel == nil else { return }

        animationGeneration += 1
        let generation = animationGeneration
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoingLevel = level
            slideDirection = goingBack ? -1 : 1
            slideProgress = 0
            level = destination
        }

        Task { @MainActor in
            // Give SwiftUI one frame to commit both panels at their starting
            // offsets before driving them across the clipped viewport.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.easeInOut(duration: 0.22)) {
                slideProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(230))
            guard generation == animationGeneration else { return }
            outgoingLevel = nil
        }
    }

    private func goBack() {
        let destination: ComposerModelPickerLevel
        switch level {
        case .root:
            return
        case .model where providerFilter != nil:
            destination = .provider
        default:
            destination = .root
        }
        query = ""
        navigate(to: destination, goingBack: true)
    }

    private func selectHarness(_ descriptor: HarnessDescriptor) {
        if descriptor.id == controller.harness.id {
            navigate(to: .root, goingBack: true)
            return
        }
        let projectPath = controller.projectPath
        onDismiss()
        Task { await state.startNewSession(projectPath: projectPath, harnessOverride: descriptor) }
    }

    private func selectModel(_ model: PiModel) {
        Task { await controller.setModel(model) }
        providerFilter = model.provider
        navigate(to: .root, goingBack: true)
        query = ""
    }

    // MARK: - Derived

    private var currentProvider: String? { controller.model?.provider }

    private var providers: [String] {
        Array(Set(controller.availableModels.map(\.provider)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var filteredModels: [PiModel] {
        let scoped = providerFilter.map { provider in
            controller.availableModels.filter { $0.provider == provider }
        } ?? controller.availableModels
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = scoped.sorted {
            if $0.provider != $1.provider {
                return $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        guard !needle.isEmpty else { return sorted }
        return sorted.filter {
            $0.provider.localizedCaseInsensitiveContains(needle)
                || $0.id.localizedCaseInsensitiveContains(needle)
                || $0.displayName.localizedCaseInsensitiveContains(needle)
                || $0.qualifiedID.localizedCaseInsensitiveContains(needle)
        }
    }

    private var modelGroups: [(provider: String, models: [PiModel])] {
        let grouped = Dictionary(grouping: filteredModels, by: \.provider)
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { (provider: $0, models: grouped[$0] ?? []) }
    }

    private var fittedHeight: CGFloat {
        ComposerModelPickerLayout.height(
            for: level,
            harnessCount: state.harnesses.usableHarnesses.count,
            providerCount: providers.count,
            reasoningCount: controller.thinkingLevels.count,
            modelCount: filteredModels.count,
            modelGroupCount: modelGroups.count
        )
    }

    private var emptyDescription: String {
        if query.isEmpty {
            return "\(controller.harness.displayName) did not return any compatible models."
        }
        return "Try a provider, model name, or qualified model ID."
    }

    private func isSelected(_ model: PiModel) -> Bool {
        controller.model?.qualifiedID == model.qualifiedID
    }
}
