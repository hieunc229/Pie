//
//  SettingsComponents.swift
//  PiCode
//
//  The building blocks of a settings page: a scrolling column of titled
//  sections, each a rounded card of rows separated by hairlines.
//

import SwiftUI

enum SettingsMetrics {
    /// The pinned title band; pages leave this much room above their content.
    static let headerHeight: CGFloat = 96
}

/// A page's scrolling column of sections.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, SettingsMetrics.headerHeight)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A heading, an optional caption, and a card of rows.
struct SettingsSection<Content: View>: View {
    var title: String?
    var caption: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.system(size: 16, weight: .medium))
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                _VariadicView.Tree(SettingsDividedLayout()) { content }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AppTheme.settingsCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.cardStroke, lineWidth: 1)
            )
        }
    }
}

/// Lays children out with a hairline between each.
private struct SettingsDividedLayout: _VariadicView_UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != last {
                    Rectangle().fill(AppTheme.cardStroke).frame(height: 1).padding(.horizontal, 16)
                }
            }
        }
    }
}

/// The label/description pair every row and block uses, so type stays uniform.
struct SettingsLabel: View {
    var title: String
    var detail: String?

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 14, weight: .medium))
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A title with an optional description on the left, a control on the right.
struct SettingsRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            SettingsLabel(title, detail: detail)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

/// A free-form block inside a card, with the card's padding.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The soft grey pill button used for row actions ("Change", "View plans").
struct SettingsPillButtonStyle: ButtonStyle {
    var prominent = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent ? AppTheme.prominentPillText : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(prominent ? AppTheme.prominentPillFill : AppTheme.railSelection.opacity(0.7))
            )
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == SettingsPillButtonStyle {
    static var settingsPill: SettingsPillButtonStyle { SettingsPillButtonStyle() }
    static var settingsPillProminent: SettingsPillButtonStyle { SettingsPillButtonStyle(prominent: true) }
}

/// A dropdown: plain text for the current value (first letter capitalised) with a
/// down chevron on the right. Opens a menu of the options.
struct Dropdown<Value: Hashable>: View {
    struct Option {
        var label: String
        var value: Value
    }

    @Binding var selection: Value
    var options: [Option]

    init(selection: Binding<Value>, options: [Option]) {
        _selection = selection
        self.options = options
    }

    init(selection: Binding<Value>, values: [Value], label: @escaping (Value) -> String) {
        _selection = selection
        options = values.map { Option(label: label($0), value: $0) }
    }

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label.capitalizedFirst, systemImage: "checkmark")
                    } else {
                        Text(option.label.capitalizedFirst)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel.capitalizedFirst)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                HugeIcon(name: "arrow-down-01")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
