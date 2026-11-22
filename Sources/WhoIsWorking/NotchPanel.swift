import AgentCore
import AppKit
import Combine
import SwiftUI

/// Geometry and open/closed state of the notch window.
@MainActor
final class NotchModel: ObservableObject {
    @Published var expanded = false
    /// False on screens without a notch: the collapsed state is then a small pill, drawn only with wings.
    @Published var hasNotch = true
    @Published var notchWidth: CGFloat = 185
    @Published var notchHeight: CGFloat = 32
    /// Natural height of the expanded panel's content, measured by the view.
    @Published var contentHeight: CGFloat = 160
    @Published var maxBodyHeight: CGFloat = 520

    static let wing: CGFloat = 70
    static let panelWidth: CGFloat = 560
    static let pillGap: CGFloat = 16
    static let bodyPadding: CGFloat = 10 + 14  // top gap below the notch + bottom padding

    var bodyHeight: CGFloat { min(contentHeight, maxBodyHeight) }
    var expandedHeight: CGFloat { notchHeight + Self.bodyPadding + bodyHeight }

    func collapsedWidth(wings: Bool) -> CGFloat {
        if hasNotch { return wings ? notchWidth + 2 * Self.wing : notchWidth }
        return wings ? 2 * Self.wing + Self.pillGap : notchWidth
    }

    func shapeSize(wings: Bool) -> CGSize {
        expanded
            ? CGSize(width: Self.panelWidth, height: expandedHeight)
            : CGSize(width: collapsedWidth(wings: wings), height: notchHeight)
    }
}

/// Lets buttons respond to the first click even though the panel never becomes key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Borderless, non-activating panel pinned over the notch. Click-through while collapsed;
/// hover is detected by polling the cursor, as in the spike.
@MainActor
final class NotchPanelController {
    let model = NotchModel()
    private let store: SessionStore
    private let actions: AppActions
    private var panel: NSPanel!
    private var timer: Timer?
    private var insideSince: Date?
    private var outsideSince: Date?
    private var shownDoneIds: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []
    private let forcedOpen = ProcessInfo.processInfo.environment["WHOISWORKING_FORCE"] == "expanded"
    private var holdOpen = false

    static let openDwell: TimeInterval = 0.15
    static let closeGrace: TimeInterval = 0.25

    init(store: SessionStore, actions: AppActions) {
        self.store = store
        self.actions = actions
    }

    func show() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView(model: model, store: store, actions: actions))
        layout()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        if forcedOpen { setExpanded(true) }
        if let dir = ProcessInfo.processInfo.environment["WHOISWORKING_SNAPSHOT"] { scheduleSnapshots(to: dir) }
    }

    // MARK: Debug snapshots

    /// Renders this window's own view to PNGs (collapsed, then expanded). Needs no screen-recording permission
    /// because it draws the app's own view hierarchy, not the screen.
    private func scheduleSnapshots(to dir: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            snapshot(to: "\(dir)/collapsed.png")
            holdOpen = true
            setExpanded(true)
            try? await Task.sleep(for: .seconds(1.5))
            snapshot(to: "\(dir)/expanded.png")
            holdOpen = false
            if !forcedOpen { setExpanded(false) }
            // Settings window, if open: AppKit-backed, so cacheDisplay works there.
            if let window = NSApp.windows.first(where: { $0.title == "Who's Working Settings" && $0.isVisible }),
               let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/settings.png"))
            }
        }
    }

    private func snapshot(to path: String) {
        let size = panel.frame.size
        let view = NotchRootView(model: model, store: store, actions: actions)
            .frame(width: size.width, height: size.height)
            .background(Color(white: 0.85))  // stands in for the menu bar / desktop
            .environment(\.snapshotMode, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = panel.screen?.backingScaleFactor ?? 2
        guard let image = renderer.cgImage else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Prefer the built-in display with a notch; otherwise the main screen with the pill fallback.
    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    func layout() {
        guard let screen, let panel else { return }
        let top = screen.safeAreaInsets.top
        let pretendNoNotch = ProcessInfo.processInfo.environment["WHOISWORKING_NO_NOTCH"] == "1"  // debug: pill layout
        if top > 0, !pretendNoNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.hasNotch = true
            model.notchHeight = top
            model.notchWidth = screen.frame.width - left.width - right.width
        } else {
            model.hasNotch = false
            model.notchHeight = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
            model.notchWidth = 160  // hover zone when nothing is drawn
        }
        model.maxBodyHeight = min(560, screen.frame.height * 0.6)
        let width = NotchModel.panelWidth + 80
        let height = model.notchHeight + NotchModel.bodyPadding + model.maxBodyHeight + 40
        panel.setFrame(
            NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height),
            display: true)
    }

    private func topRect(width: CGFloat, height: CGFloat) -> NSRect {
        guard let screen else { return .zero }
        // +4 on top so a cursor pinned to the screen edge still counts.
        return NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height + 4)
    }

    private func tick() {
        guard !forcedOpen, !holdOpen else { return }
        let mouse = NSEvent.mouseLocation
        let now = Date()
        if model.expanded {
            let area = topRect(width: NotchModel.panelWidth, height: model.expandedHeight).insetBy(dx: -14, dy: -14)
            if area.contains(mouse) {
                outsideSince = nil
            } else {
                if outsideSince == nil { outsideSince = now }
                if now.timeIntervalSince(outsideSince!) > Self.closeGrace { setExpanded(false) }
            }
        } else {
            let wings = store.summary.showsWings
            let area = topRect(width: model.collapsedWidth(wings: wings), height: model.notchHeight)
            if area.contains(mouse) {
                if insideSince == nil { insideSince = now }
                if now.timeIntervalSince(insideSince!) > Self.openDwell { setExpanded(true) }
            } else {
                insideSince = nil
            }
        }
    }

    func setExpanded(_ value: Bool) {
        insideSince = nil
        outsideSince = nil
        guard model.expanded != value else { return }
        if value {
            shownDoneIds = Set(store.summary.done.filter { $0.state == .doneUnseen }.map(\.id))
        } else {
            // Done sessions the user just looked at become idle.
            store.markViewed(Array(shownDoneIds))
            shownDoneIds = []
        }
        model.expanded = value
        panel.ignoresMouseEvents = !value
    }

    /// Called after the user acts on a row, so the panel gets out of the way.
    func collapse() { setExpanded(false) }
}
