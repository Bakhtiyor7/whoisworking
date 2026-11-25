import AgentCore
import AppKit
import SwiftUI

enum Palette {
    static let amber = Color(red: 1.0, green: 0.624, blue: 0.04)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let dim = Color(white: 0.68)
    static let card = Color(white: 0.11)
    static let mark = Color(white: 0.23)
}

extension EnvironmentValues {
    /// True while rendering a debug snapshot with ImageRenderer.
    @Entry var snapshotMode = false
}

/// What the views can ask the app to do.
@MainActor
final class AppActions: ObservableObject {
    var openSession: (Session) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var hooksInstalled: () -> Bool = { false }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var store: SessionStore
    @ObservedObject var setup: SetupModel
    let actions: AppActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = store.summary
        // One value decides what the collapsed notch draws and where the pointer opens it.
        let collapsed = CollapsedNotch(summary: summary, setup: setup.prompt)
        let wings = collapsed.showsWings
        let size = model.shapeSize(wings: wings)
        let radius: CGFloat = model.expanded ? 28 : (model.hasNotch ? 12 : 10)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        // On screens without a notch nothing is drawn unless there are wings or the panel is open.
        let visible = model.expanded || model.hasNotch || wings
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82)

        ZStack(alignment: .top) {
            shape.fill(.black)
            if model.expanded {
                ExpandedPanel(
                    model: model, setup: setup, summary: summary, now: store.now, actions: actions,
                    socketError: store.socketError
                )
                .padding(.top, model.notchHeight + 10)
                .padding([.horizontal, .bottom], 14)
                .transition(.opacity)
            } else {
                switch collapsed {
                case .needsYou(let count, let wait):
                    Wings(count: count, wait: wait)
                        .frame(height: model.notchHeight)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                case .setup:
                    SetupWings()
                        .frame(height: model.notchHeight)
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                case .hidden:
                    EmptyView()
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(animation, value: model.expanded)
        .animation(animation, value: wings)
        .animation(animation, value: model.contentHeight)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

struct Wings: View {
    let count: Int
    let wait: TimeInterval

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(Palette.amber).frame(width: 10, height: 10)
                Text("\(count)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            Spacer()
            Text(formatElapsed(wait)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Palette.dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(count == 1 ? "session needs" : "sessions need") you, longest wait \(formatElapsedSpoken(wait))")
    }
}

struct SectionLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

struct AgentMark: View {
    let agent: AgentKind

    private static let claudeCodeIcon = NSImage(data: Data(PackageResources.claudecode_png))
    private static let codexIcon = NSImage(data: Data(PackageResources.codex_png))
    private static let cursorIcon = NSImage(data: Data(PackageResources.cursor_png))
    private static let openCodeIcon = NSImage(data: Data(PackageResources.opencode_png))
    private static let antigravityIcon = NSImage(data: Data(PackageResources.antigravity_png))

    private var icon: NSImage? {
        switch agent {
        case .claudeCode: Self.claudeCodeIcon
        case .codex: Self.codexIcon
        case .cursor: Self.cursorIcon
        case .openCode: Self.openCodeIcon
        case .antigravity: Self.antigravityIcon
        }
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Text(agent.shortCode)
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Palette.mark, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// State glyph: colour plus a distinct shape, so it reads without colour.
struct StateIcon: View {
    let state: SessionState
    /// A running agent process with no hook events yet: state unknown, so not a "done" tick.
    var placeholder = false

    var body: some View {
        Group {
            switch state {
            case .needsApproval: Image(systemName: "hand.raised.fill").foregroundStyle(Palette.amber)
            case .waitingForReply: Image(systemName: "bubble.left.fill").foregroundStyle(Palette.amber)
            case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.red)
            case .working: Image(systemName: "circle.dotted").foregroundStyle(Palette.dim)
            case .doneUnseen: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
            case .idle where placeholder: Image(systemName: "terminal").foregroundStyle(Palette.dim)
            case .idle: Image(systemName: "checkmark.circle").foregroundStyle(Palette.dim)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 14)
        .accessibilityHidden(true)
    }
}

extension SessionState {
    var spoken: String {
        switch self {
        case .working: "working"
        case .needsApproval: "needs approval"
        case .waitingForReply: "waiting for your reply"
        case .doneUnseen: "done"
        case .idle: "idle"
        case .error: "error"
        }
    }
}

struct SessionRow: View {
    let session: Session
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let elapsed = now.timeIntervalSince(session.stateSince)
        Button(action: action) {
            HStack(spacing: 10) {
                AgentMark(agent: session.agent)
                Text(session.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 150, alignment: .leading)
                StateIcon(state: session.state, placeholder: session.isPlaceholder)
                Text(session.rowDetail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(formatElapsed(elapsed)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.dim)
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(Color(white: hovering ? 0.11 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(session.cwd ?? session.displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.displayName), \(session.agent.displayName), \(session.state.spoken), \(session.rowDetail), \(formatElapsedSpoken(elapsed))")
        .accessibilityHint("Opens the session's app")
        .accessibilityAddTraits(.isButton)
    }
}

struct NeedsYouCard: View {
    let session: Session
    let now: Date
    let action: () -> Void
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let wait = now.timeIntervalSince(session.stateSince)
        let tint = session.state == .error ? Palette.red : Palette.amber
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentMark(agent: session.agent)
                Text(session.displayName).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer()
                Text("\(session.agent.displayName) · \(wait < 5 ? "just now" : "waiting \(formatElapsed(wait))")")
                    .font(.system(size: 12)).monospacedDigit().foregroundStyle(Palette.dim)
            }
            if let detail = session.requestDetail, !detail.isEmpty {
                let text = Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if snapshotMode {
                        text.lineLimit(6)
                    } else {
                        ScrollView(.vertical) { text }
                            .frame(maxHeight: 96)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 8) {
                StateIcon(state: session.state, placeholder: session.isPlaceholder)
                Text(session.requestTitle).font(.system(size: 12)).foregroundStyle(Palette.dim).lineLimit(2)
                Spacer()
                Button(action: action) {
                    HStack(spacing: 6) {
                        Text("Open session")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open session \(session.displayName)")
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.displayName), \(session.state.spoken), \(session.requestTitle), waiting \(formatElapsedSpoken(wait))")
    }
}

struct ExpandedPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var setup: SetupModel
    let summary: NotchSummary
    let now: Date
    let actions: AppActions
    let socketError: String?

    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        if snapshotMode {
            // ImageRenderer leaves ScrollView contents blank; lay the same content out directly.
            content.frame(height: model.bodyHeight, alignment: .top).clipped()
        } else {
            scrolling
        }
    }

    private var scrolling: some View {
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeight = $0 }
        }
        .scrollIndicators(model.contentHeight > model.maxBodyHeight ? .automatic : .never)
        .scrollDisabled(model.contentHeight <= model.maxBodyHeight)
        .frame(height: model.bodyHeight)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 12) {
            if let socketError {
                Label(socketError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Palette.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
            }
            // A session that needs the user stays first, above setup (UI-17).
            if !summary.needsYou.isEmpty {
                VStack(spacing: 6) {
                    SectionLabel(text: "NEEDS YOU", color: Palette.amber)
                    ForEach(summary.needsYou) { session in
                        NeedsYouCard(session: session, now: now) { actions.openSession(session) }
                    }
                }
            }
            if setup.prompt.showsCard {
                SetupCard(setup: setup)
            } else if summary.isEmpty {
                EmptyStateView(hooksInstalled: actions.hooksInstalled(), openSettings: actions.openSettings)
            }
            if !summary.working.isEmpty {
                VStack(spacing: 2) {
                    SectionLabel(text: "WORKING", color: Palette.dim)
                    ForEach(summary.working) { session in
                        SessionRow(session: session, now: now) { actions.openSession(session) }
                    }
                }
            }
            if !summary.done.isEmpty {
                VStack(spacing: 2) {
                    SectionLabel(text: "DONE", color: Palette.green)
                    ForEach(summary.done) { session in
                        SessionRow(session: session, now: now) { actions.openSession(session) }
                    }
                }
            }
            HStack {
                Spacer()
                Button(action: actions.openSettings) {
                    Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
                        .font(.system(size: 13))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.dim)
                .help("Who's Working settings")
                .accessibilityLabel("Who's Working settings")
            }
        }
    }
}

struct EmptyStateView: View {
    let hooksInstalled: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz").font(.system(size: 22)).foregroundStyle(Palette.dim)
            Text("No agent sessions").font(.system(size: 14, weight: .semibold))
            Text(hooksInstalled
                ? "Start Claude Code or Codex and its sessions will show up here."
                : "Claude Code and Codex sessions show up here. Install the hooks for live status.")
                .font(.system(size: 12)).foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
            if !hooksInstalled {
                Button("Open Settings", action: openSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.amber)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}
