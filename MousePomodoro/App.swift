import SwiftUI
import Combine
import UserNotifications

@main
struct MousePomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Borderless panels can't become key by default, which would make the buttons
/// inside the compact strip ignore the first click.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private static let compactSize = NSSize(width: 232, height: 84)
    private static let compactFrameName = "MousePomodoroCompactPanel"

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var compactPanel: FloatingPanel?
    private let engine = TimerEngine()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = NSImage(named: "icon-mouse-face")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 16, height: 16)
            button.image = icon
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        statusItem = item

        let hosting = NSHostingController(rootView: ContentView(engine: engine))
        // We size the popover ourselves (see below); without this, NSHostingController's
        // own automatic preferredContentSize-driven resizing races our manual updates
        // whenever the content changes size while the popover is already shown.
        hosting.sizingOptions = []

        let pop = NSPopover()
        pop.contentSize = NSSize(width: 340, height: engine.popoverHeight)
        pop.animates = false
        pop.behavior = .transient
        pop.contentViewController = hosting
        popover = pop

        compactPanel = makeCompactPanel()

        Publishers.CombineLatest3(engine.$view, engine.$overlay, engine.$statsHasStreakChip).sink { [weak self] view, overlay, chip in
            // Deferred to the next run loop turn so SwiftUI finishes laying out the
            // new content first — setting contentSize synchronously here could race
            // the hosting view's own update for the same change.
            DispatchQueue.main.async {
                self?.popover?.contentSize = NSSize(
                    width: 340,
                    height: TimerEngine.popoverHeight(view: view, overlay: overlay, statsStreakChip: chip)
                )
            }
        }
        .store(in: &cancellables)

        // Remaining time next to the menu bar icon (Focus/Break only, if enabled).
        Publishers.CombineLatest3(engine.$view, engine.$remaining, engine.$showMenuBarTime)
            .map { TimerEngine.menuBarTimeText(view: $0, remaining: $1, enabled: $2) }
            .removeDuplicates()
            .sink { [weak self] text in self?.setMenuBarTitle(text) }
            .store(in: &cancellables)

        engine.$compact.dropFirst().removeDuplicates().sink { [weak self] compact in
            DispatchQueue.main.async { self?.compactChanged(compact) }
        }
        .store(in: &cancellables)

        // A persisted compact mode comes back as the floating strip, not a popover.
        if engine.compact { showCompactPanel() }
    }

    // MARK: - Menu bar title

    private func setMenuBarTitle(_ text: String?) {
        guard let button = statusItem?.button else { return }
        if let text {
            // Monospaced digits so the item doesn't jitter in width as the seconds tick.
            button.attributedTitle = NSAttributedString(
                string: " " + text,
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)]
            )
            button.imagePosition = .imageLeading
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
    }

    // MARK: - Sizing / panels

    /// The minimized strip is a free-floating, draggable panel — not attached to
    /// the menu bar like the full popover.
    private func makeCompactPanel() -> FloatingPanel {
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.compactSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ContentView(engine: engine))

        if panel.setFrameUsingName(Self.compactFrameName) {
            panel.setContentSize(Self.compactSize)
        } else if let screen = NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: area.maxX - Self.compactSize.width - 16,
                y: area.maxY - Self.compactSize.height - 16
            ))
        }
        panel.setFrameAutosaveName(Self.compactFrameName)
        return panel
    }

    private func showCompactPanel() {
        compactPanel?.orderFrontRegardless()
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func compactChanged(_ compact: Bool) {
        if compact {
            popover?.performClose(nil)
            showCompactPanel()
        } else {
            compactPanel?.orderOut(nil)
            showPopover()
        }
    }

    /// "Open the app" — whichever form is current.
    private func showApp() {
        if engine.compact {
            showCompactPanel()
        } else {
            showPopover()
        }
    }

    @objc private func statusItemClicked() {
        if engine.compact {
            showCompactPanel()
        } else if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPopover()
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in self.showApp() }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
