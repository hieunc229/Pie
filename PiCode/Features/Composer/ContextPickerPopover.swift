//
//  ContextPickerPopover.swift
//  PiCode
//
//  One dropdown style for the composer's context strip: a search field, an
//  optional section title, rows with a glyph / title / subtitle / checkmark, and
//  footer actions below a rule.
//

import SwiftUI

struct ContextPickerItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var systemImage: String
    var isSelected = false
}

struct ContextPickerAction: Identifiable {
    var id: String { title }
    var title: String
    var systemImage: String
    var perform: () -> Void
}

struct ContextPickerPopover: View {
    var searchPrompt: String
    var heading: String?
    var items: [ContextPickerItem]
    var actions: [ContextPickerAction] = []
    var onSelect: (ContextPickerItem) -> Void
    var onDismiss: () -> Void

    @State private var query = ""
    @State private var hovered: String?
    @FocusState private var searchFocused: Bool

    private var filtered: [ContextPickerItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = filtered.first { choose(first) }
                    }
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.horizontal, 8)

            if let heading {
                Text(heading)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { row($0) }
                    if filtered.isEmpty {
                        Text("No matches")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 260)

            if !actions.isEmpty {
                Divider().padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(actions) { action in
                        Button {
                            onDismiss()
                            action.perform()
                        } label: {
                            rowLabel(image: action.systemImage, title: action.title, subtitle: nil, selected: false)
                        }
                        .buttonStyle(ContextPickerRowStyle(isHovered: hovered == action.id))
                        .onHover { hovered = $0 ? action.id : nil }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 300)
        .onAppear { searchFocused = true }
    }

    private func row(_ item: ContextPickerItem) -> some View {
        Button { choose(item) } label: {
            rowLabel(image: item.systemImage, title: item.title, subtitle: item.subtitle, selected: item.isSelected)
        }
        .buttonStyle(ContextPickerRowStyle(isHovered: hovered == item.id))
        .onHover { hovered = $0 ? item.id : nil }
    }

    private func rowLabel(image: String, title: String, subtitle: String?, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: image)
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if selected { Image(systemName: "checkmark").font(.system(size: 12)) }
        }
        .font(.system(size: 13.5))
        .contentShape(Rectangle())
    }

    private func choose(_ item: ContextPickerItem) {
        onDismiss()
        onSelect(item)
    }
}

private struct ContextPickerRowStyle: ButtonStyle {
    var isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(isHovered || configuration.isPressed ? 0.1 : 0))
            )
    }
}
