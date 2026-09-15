//
//  ContentHeader.swift
//  PiCode
//
//  The content column's own header.
//
//  It replaces the window's navigation title: the transcript's own fill carries
//  the folder and the project name on the left, and the notification bell, the
//  workspace menu and the right panel's toggle on the right, with a hairline
//  rule under it. The model name is deliberately not shown — it lives in the
//  inspector, where the session's own facts are, and the header stays a context
//  line rather than a status strip.
//  Drawing it on the transcript's background rather than the toolbar's is what
//  keeps the column reading as one surface, from this line down to the composer.
//

import SwiftUI

/// The measurements the detail column's header and any sibling titlebar-band
/// surface share, so a page that replaces the transcript lines up with it rather
/// than approximating it.
enum ContentHeaderMetrics {
    /// The leading inset for the header's own line: clear of the traffic lights
    /// and the sidebar toggle when the sidebar is closed, close to the window's
    /// edge when it is open. Measured against the running window, not derived.
    static func leadingInset(isSidebarVisible: Bool) -> CGFloat {
        isSidebarVisible ? 14 : 124
    }
}

/// The detail column's header: what the conversation belongs to, and the control
/// for the panel beside it.
struct ContentHeader: View {
    /// The project the session runs in. `nil` hides the whole context line: the
    /// folder glyph is the mark that makes the line a context line, so it is not
    /// drawn without the name it introduces.
    let projectName: String?
    /// Whether the sidebar is showing. When it is closed the content column reaches
    /// the window's leading edge, so its header starts clear of the traffic lights
    /// and the sidebar toggle rather than under them.
    let isSidebarVisible: Bool
    /// How many notifications are new. Above zero the bell carries a red badge.
    let unreadNotificationCount: Int
    /// Whether the right panel is currently showing the notification list, which
    /// is what the bell's tint states.
    let isShowingNotifications: Bool
    let onToggleNotifications: () -> Void
    /// Whether the inspector is open on an artifact — the one fact the panel
    /// toggle's tint states. It is false while the bell owns the panel, so the two
    /// buttons are never lit at once.
    let isInspectorVisible: Bool
    let onToggleInspector: () -> Void

    /// Whether the terminal panel is open. It tints the workspace menu's square
    /// so the menu states that one of its own actions is currently on.
    let isTerminalVisible: Bool
    let onToggleTerminal: () -> Void
    let onOpenInFinder: () -> Void
    let onOpenInVSCode: () -> Void

    /// The transcript's own colour, so the header is part of the conversation
    /// surface and not a bar above it.
    private var backdrop: Color { AppTheme.background }

    /// Whether the pointer is over one of the header's controls. Their grey lifts
    /// to full strength on hover, which is the only hover feedback a plain icon
    /// button gets.
    @State private var isHoveringNotifications = false
    @State private var isHoveringInspector = false
    @State private var isHoveringWorkspace = false

    /// The sidebar is closed, so the content reaches the window's leading edge.
    /// The traffic lights run to about 64pt and the system's sidebar toggle to
    /// about 101pt; this starts the header's own line just past the toggle.
    /// Measured against the running window, not derived.
    private var leadingInset: CGFloat { ContentHeaderMetrics.leadingInset(isSidebarVisible: isSidebarVisible) }

    var body: some View {
        HStack(spacing: 12) {
            projectContext
            Spacer(minLength: 8)
            // A gap of their own: the three controls are neighbours on one row,
            // not a single control split apart. The bell leads, then the workspace
            // menu, then the panel toggle — the two state lights bracket the menu
            // that is not one.
            HStack(spacing: 16) {
                notificationsToggle
                workspaceMenu
                inspectorToggle
            }
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, 14)
        // The header occupies the window's top band — the row the traffic lights
        // and the sidebar's search icon are centred on — so its own line is the
        // first thing in the column rather than a second header under the window's
        // edge. The top and bottom padding are equal so the line sits centred in
        // its band rather than high in it.
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(backdrop)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
        }
    }

    /// The folder glyph and the facts beside it.
    ///
    /// The glyph is the one mark on the line, and it is tertiary so it stays
    /// quieter than the name it introduces. It is drawn one point larger than the
    /// header's small image scale, because a smaller folder read as a smudge rather
    /// than a folder. The project is secondary: the line carries one fact now that
    /// the model name is hidden.
    @ViewBuilder
    private var projectContext: some View {
        if projectName != nil {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: Typography.baseSize))
                    .foregroundStyle(.tertiary)
                if let projectName {
                    Text(projectName)
                        .font(Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// The workspace menu, drawn to the left of the bell: the actions that act on
    /// the project as a whole rather than on the conversation — the terminal
    /// panel, and opening the folder in Finder or an editor. A menu rather than
    /// three more icons keeps the header's right edge from turning into a strip.
    ///
    /// The square is always dimmed and lifts to full ink only under the pointer:
    /// it is a menu, not a state control. Which item is on is carried by the item's
    /// own label ("Hide Terminal") and by the panel being visibly open below, so
    /// the icon does not need a lit state of its own.
    private var workspaceMenu: some View {
        Menu {
            Button(action: onToggleTerminal) {
                Label(isTerminalVisible ? "Hide Terminal" : "Show Terminal",
                      systemImage: "terminal")
            }
            Divider()
            Button(action: onOpenInFinder) {
                Label("Open in Finder", systemImage: "folder")
            }
            Button(action: onOpenInVSCode) {
                Label("Open in VS Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        } label: {
            Image(systemName: "equal.square")
                .imageScale(.medium)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHoveringWorkspace = $0 }
        // Dimming has to be applied to the `Menu`, not to the glyph: a
        // `borderlessButton` menu snapshots its label as a template image and
        // drops drawing modifiers set inside it (`.foregroundStyle` and even
        // `.opacity` on the `Image` both render at full ink). Compositing the
        // menu itself is the one form that survives, and it dims only the label —
        // the popped-up items are their own window and stay at full strength.
        .opacity(isHoveringWorkspace ? 1 : 0.55)
        .help("Workspace actions")
        .accessibilityLabel("Workspace actions")
    }

    /// The notifications bell, drawn first, to the left of the workspace menu. Its
    /// tint states whether the panel is showing notifications, and a red badge
    /// carries the count until the list is opened.
    private var notificationsToggle: some View {
        Button(action: onToggleNotifications) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .imageScale(.medium)
                if unreadNotificationCount > 0 {
                    Text(unreadNotificationCount > 99 ? "99+" : "\(unreadNotificationCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        // Kept inside the bell's own width: a wider offset
                        // reached across the gap to its neighbour and touched the
                        // workspace menu, so the two read as one blob whenever a
                        // count was showing. The offset stops short at any count.
                        .offset(x: 5, y: -5)
                }
            }
            // A fixed width, because the badge is laid out inside the ZStack: a
            // wider badge ("99+") would otherwise widen the button and shove the
            // workspace menu beside it the moment a notification arrived. The
            // frame does not clip, so the badge still overhangs into its own gap.
            .frame(width: 15, height: 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHoveringNotifications = $0 }
        .foregroundStyle(controlTint(isActive: isShowingNotifications, isHovering: isHoveringNotifications))
        .help(isShowingNotifications ? "Hide notifications" : "Show notifications")
        .accessibilityLabel(unreadNotificationCount > 0
            ? "Notifications, \(unreadNotificationCount) unread"
            : "Notifications")
    }

    /// The right panel's toggle. Its tint — full ink while the panel is open on an
    /// artifact, the dimmed primary ink otherwise — is the only place that fact is
    /// drawn, which is why the button is a plain icon rather than a filled control.
    private var inspectorToggle: some View {
        Button(action: onToggleInspector) {
            Image(systemName: "sidebar.right")
                .imageScale(.medium)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .onHover { isHoveringInspector = $0 }
        .foregroundStyle(controlTint(isActive: isInspectorVisible, isHovering: isHoveringInspector))
        .help(isInspectorVisible ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
        .accessibilityLabel("Toggle Inspector")
    }

    /// The tint the two panel toggles share: full ink while their panel is open,
    /// otherwise the primary ink dimmed until the pointer reaches it. The active
    /// state is the bright one — white in the dark appearance — so only one button
    /// can look lit. Using `primary` rather than a literal white keeps the glyph
    /// readable on the light appearance too.
    private func controlTint(isActive: Bool, isHovering: Bool) -> Color {
        if isActive { return .primary }
        return hoverTint(isHovering: isHovering)
    }

    /// The hover-only tint: dimmed until the pointer arrives, then the same full
    /// ink a lit panel toggle uses. The workspace menu uses this alone, so its
    /// square reads as an affordance rather than as another status light.
    private func hoverTint(isHovering: Bool) -> Color {
        isHovering ? .primary : .primary.opacity(0.55)
    }
}
