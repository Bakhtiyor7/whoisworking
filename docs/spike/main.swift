import AppKit
import SwiftUI

// Throwaway spike. Sample data only; no agent integration.
// PERCH_FORCE=expanded keeps the panel open (for screenshots).

let amber = Color(red: 1.0, green: 0.624, blue: 0.04)
let green = Color(red: 0.19, green: 0.82, blue: 0.35)
let dim = Color(white: 0.68)

@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var needsYou = true

    var notchWidth: CGFloat = 200
    var notchHeight: CGFloat = 37

    static let wing: CGFloat = 70
    static let panelWidth: CGFloat = 560
    static let panelBody: CGFloat = 400

    var collapsedWidth: CGFloat { needsYou ? notchWidth + 2 * Self.wing : notchWidth }
    var expandedHeight: CGFloat { notchHeight + Self.panelBody }
    var shapeSize: CGSize {
        expanded
            ? CGSize(width: Self.panelWidth, height: expandedHeight)
            : CGSize(width: collapsedWidth, height: notchHeight)
    }
}

struct NotchView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        let size = model.shapeSize
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: model.expanded ? 28 : 12,
            bottomTrailingRadius: model.expanded ? 28 : 12,
            style: .continuous
        )
        ZStack(alignment: .top) {
            shape.fill(.black)
            if model.expanded {
                ExpandedPanel(model: model)
                    .padding(.top, model.notchHeight + 10)
                    .padding([.horizontal, .bottom], 14)
                    .transition(.opacity)
            } else if model.needsYou {
                Wings()
                    .frame(height: model.notchHeight)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.expanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.needsYou)
        .foregroundStyle(.white)
    }
}

struct Wings: View {
    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Circle().fill(amber).frame(width: 10, height: 10)
                Text("1").font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Text("2m").font(.system(size: 13, weight: .medium)).foregroundStyle(dim)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("1 session needs you, waiting 2 minutes")
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
    }
}

struct AgentMark: View {
    let code: String
    var body: some View {
        Text(code)
            .font(.system(size: 10, weight: .bold))
            .frame(width: 24, height: 24)
            .background(Color(white: 0.23), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct SessionRow: View {
    let code: String
    let name: String
    let detail: String
    let time: String
    @State private var hovering = false

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                AgentMark(code: code)
                Text(name).font(.system(size: 14, weight: .semibold)).frame(width: 150, alignment: .leading)
                Text(detail).font(.system(size: 12)).foregroundStyle(dim)
                Spacer()
                Text(time).font(.system(size: 12)).foregroundStyle(dim)
            }
            .padding(.horizontal, 6)
            .frame(height: 44)
            .background(Color(white: hovering ? 0.11 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ExpandedPanel: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(spacing: 12) {
            if model.needsYou {
                VStack(spacing: 6) {
                    SectionLabel(text: "NEEDS YOU", color: amber)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            AgentMark(code: "CC")
                            Text("api-server").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("Claude Code · waiting 2m").font(.system(size: 12)).foregroundStyle(dim)
                        }
                        Text("npm test -- --coverage")
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        HStack {
                            Text("Wants permission to run a command").font(.system(size: 12)).foregroundStyle(dim)
                            Spacer()
                            Button(action: {}) {
                                HStack(spacing: 6) {
                                    Text("Open session")
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .frame(height: 36)
                                .background(amber, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }

            VStack(spacing: 2) {
                SectionLabel(text: "WORKING", color: dim)
                SessionRow(code: "CX", name: "personal-website", detail: "Editing Header.tsx", time: "8m")
                SessionRow(code: "CC", name: "fitness-project", detail: "Running tests", time: "14m")
            }

            VStack(spacing: 2) {
                SectionLabel(text: "DONE", color: green)
                SessionRow(code: "CU", name: "ai-translate", detail: "Added glossary import", time: "1m")
            }

            Spacer(minLength: 0)

            // Spike-only controls.
            HStack {
                Button(model.needsYou ? "Spike: clear “needs you”" : "Spike: simulate “needs you”") {
                    model.needsYou.toggle()
                }
                Spacer()
                Button("Quit spike") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(dim)
            .padding(.horizontal, 6)
        }
    }
}

/// Lets buttons respond to the first click even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = NotchModel()
    var panel: NSPanel!
    var timer: Timer?
    var insideSince: Date?
    var outsideSince: Date?
    let forced = ProcessInfo.processInfo.environment["PERCH_FORCE"] == "expanded"

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildPanel()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if forced { model.expanded = true; panel.ignoresMouseEvents = false }
    }

    /// Prefer the built-in display (the one with a notch).
    var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    func buildPanel() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.contentView = FirstMouseHostingView(rootView: NotchView(model: model))
        layout()
        panel.orderFrontRegardless()
    }

    func layout() {
        guard let screen else { return }
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchHeight = top
            model.notchWidth = screen.frame.width - left.width - right.width
        } else {
            // No notch: fall back to a pill the height of the menu bar.
            model.notchHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            model.notchWidth = 200
        }
        let width = NotchModel.panelWidth + 80
        let height = model.expandedHeight + 20
        panel.setFrame(
            NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height),
            display: true
        )
    }

    func topRect(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen else { return .zero }
        // +4 on top so a cursor pinned to the screen edge still counts.
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 4)
    }

    func tick() {
        guard !forced else { return }
        let mouse = NSEvent.mouseLocation
        let now = Date()
        if model.expanded {
            let area = topRect(width: NotchModel.panelWidth, height: model.expandedHeight).insetBy(dx: -14, dy: -14)
            if area.contains(mouse) {
                outsideSince = nil
            } else {
                if outsideSince == nil { outsideSince = now }
                if now.timeIntervalSince(outsideSince!) > 0.25 { setExpanded(false) }
            }
        } else {
            let area = topRect(width: model.collapsedWidth, height: model.notchHeight)
            if area.contains(mouse) {
                if insideSince == nil { insideSince = now }
                if now.timeIntervalSince(insideSince!) > 0.15 { setExpanded(true) }
            } else {
                insideSince = nil
            }
        }
    }

    func setExpanded(_ value: Bool) {
        insideSince = nil
        outsideSince = nil
        model.expanded = value
        panel.ignoresMouseEvents = !value
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
