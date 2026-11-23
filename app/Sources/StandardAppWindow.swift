import SwiftUI
import AppKit

enum StandardWindowSizing {
    static var openingScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    static func contentSize(preferred: CGSize, visibleFrame: CGRect) -> CGSize {
        contentSize(preferred: preferred, visibleFrames: [visibleFrame])
    }

    static func contentSize(preferred: CGSize, visibleFrames: [CGRect]) -> CGSize {
        // One shared size for all connected monitors. Fit the window's total
        // area, not a fraction of each dimension: portrait displays should
        // not make an otherwise comfortably fitting window narrower.
        let toolbarAllowance: CGFloat = 64
        let outerHeight = preferred.height + toolbarAllowance
        var scale: CGFloat = 1
        for frame in visibleFrames where frame.width > 0 && frame.height > 0 {
            scale = min(scale,
                        max(1, frame.width - 32) / preferred.width,
                        max(1, frame.height - 32) / outerHeight,
                        sqrt(0.34 * frame.width * frame.height / (preferred.width * outerHeight)))
        }
        return CGSize(width: floor(preferred.width * scale),
                      height: floor(max(1, outerHeight * scale - toolbarAllowance)))
    }
}

struct StandardWindowContent<Content: View>: View {
    let preferredSize: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .scrollIndicators(.hidden)
            .background(StandardAppWindow(preferredSize: preferredSize))
    }
}

/// AppKit owns window geometry. Feeding screen changes back into a fixed
/// SwiftUI frame/contentSize scene can create an unbounded constraints loop.
struct StandardAppWindow: NSViewRepresentable {
    let preferredSize: CGSize

    func makeNSView(context: Context) -> WindowAnchor {
        let view = WindowAnchor()
        view.preferredSize = preferredSize
        return view
    }
    func updateNSView(_ nsView: WindowAnchor, context: Context) {}

    final class WindowAnchor: NSView {
        var preferredSize = CGSize.zero
        private weak var configuredWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var resizeTimer: Timer?
        private var lastAppliedSize: CGSize?
        private var centerOnNextShow = true
        private var openingScreen: NSScreen?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else {
                removeObservers()
                configuredWindow = nil
                return
            }
            guard configuredWindow !== window else { return }
            removeObservers()
            configuredWindow = window
            lastAppliedSize = nil
            centerOnNextShow = true
            openingScreen = StandardWindowSizing.openingScreen

            applyWindowPolicy(window)

            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didUpdateNotification,
                                                 object: window, queue: .main) { [weak self] _ in
                guard let self, let window = self.configuredWindow else { return }
                self.applyWindowPolicy(window)
            })
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                 object: window, queue: .main) { [weak self] _ in
                self?.resizeTimer?.invalidate()
                self?.resizeTimer = nil
                self?.centerOnNextShow = true
                self?.openingScreen = nil
            })
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                 object: window, queue: .main) { [weak self] _ in
                guard let self, self.centerOnNextShow else { return }
                self.openingScreen = StandardWindowSizing.openingScreen
                self.scheduleUpdate()
            })
            observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                 object: nil, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            })
            observers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification,
                                                 object: window, queue: .main) { [weak self] _ in
                self?.scheduleUpdate()
            })
            scheduleUpdate()
        }

        private func scheduleUpdate() {
            resizeTimer?.invalidate()
            let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.resizeTimer = nil
                // A screen notification may arrive inside an AppKit drag or
                // layout transaction. Never resize while the button is down.
                guard NSEvent.pressedMouseButtons & 1 == 0 else {
                    self.scheduleUpdate()
                    return
                }
                self.updateGeometry()
            }
            resizeTimer = timer
            // Deliberately excluded from event-tracking modes during dragging.
            RunLoop.main.add(timer, forMode: .default)
        }

        private func updateGeometry() {
            guard let window = configuredWindow,
                  let screen = (centerOnNextShow ? openingScreen : window.screen) ?? NSScreen.main else { return }
            applyWindowPolicy(window)
            let size = StandardWindowSizing.contentSize(preferred: preferredSize,
                visibleFrames: NSScreen.screens.map(\.visibleFrame))
            let shouldCenter = centerOnNextShow
            centerOnNextShow = false
            if lastAppliedSize != size {
                // Record before applying: setContentSize may itself notify a
                // screen change. That next notification must be a no-op.
                lastAppliedSize = size
                window.setContentSize(size)
            }
            if shouldCenter {
                let visible = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                              y: visible.midY - window.frame.height / 2))
            }
        }

        private func applyWindowPolicy(_ window: NSWindow) {
            // SwiftUI finishes applying scene defaults after the view attaches.
            // Keep this idempotent so ordinary window updates cannot re-enable
            // fullscreen or resizing, and cannot start another layout cycle.
            window.isRestorable = false
            window.isMovable = true
            if window.styleMask.contains(.resizable) { window.styleMask.remove(.resizable) }
            let unwanted: NSWindow.CollectionBehavior = [.fullScreenPrimary, .fullScreenAuxiliary]
            let behavior = window.collectionBehavior.subtracting(unwanted).union(.fullScreenNone)
            if window.collectionBehavior != behavior { window.collectionBehavior = behavior }
            if window.standardWindowButton(.zoomButton)?.isEnabled == true {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        }

        private func removeObservers() {
            resizeTimer?.invalidate()
            resizeTimer = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        deinit { removeObservers() }
    }
}
