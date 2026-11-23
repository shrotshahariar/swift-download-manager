import AppKit
import SwiftUI

private final class MeasuringWindow: NSWindow {
    var sizeWrites = 0
    override func setContentSize(_ size: NSSize) {
        sizeWrites += 1
        super.setContentSize(size)
    }
}

@main
struct WindowSizingChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        func spin(_ mode: RunLoop.Mode = .default, seconds: TimeInterval = 0.3) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(mode: mode, before: end) }
        }
        for dimensions in [(1024.0, 700.0), (1280, 750), (1512, 920), (1920, 1040), (2560, 1400)] {
            let frame = CGRect(x: 0, y: 0, width: dimensions.0, height: dimensions.1)
            let size = StandardWindowSizing.contentSize(preferred: CGSize(width: 900, height: 680), visibleFrame: frame)
            precondition(size.width * (size.height + 64) / (frame.width * frame.height) <= 0.35)
            precondition(size.width.rounded() == size.width && size.height.rounded() == size.height)
        }
        let window = MeasuringWindow(contentRect: CGRect(x: 20, y: 20, width: 900, height: 680),
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView:
            StandardWindowContent(preferredSize: CGSize(width: 900, height: 680)) {
                NavigationSplitView {
                    Text("Sidebar").navigationSplitViewColumnWidth(min: 210, ideal: 225, max: 280)
                } detail: {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))]) {
                            ForEach(0..<20) { Text("Widget \($0)").frame(height: 140) }
                        }
                    }
                }
            })
        window.contentView?.layoutSubtreeIfNeeded()
        spin()
        precondition(!window.styleMask.contains(.resizable) && window.isMovable)
        precondition(window.collectionBehavior.contains(.fullScreenNone))
        window.styleMask.insert(.resizable)
        window.collectionBehavior.remove(.fullScreenNone)
        window.collectionBehavior.insert(.fullScreenPrimary)
        NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
        precondition(!window.styleMask.contains(.resizable))
        precondition(window.collectionBehavior.contains(.fullScreenNone))
        let opening = StandardWindowSizing.openingScreen!.visibleFrame
        precondition(abs(window.frame.midX - opening.midX) < 1 && abs(window.frame.midY - opening.midY) < 1)

        let screens = NSScreen.screens
        let sharedSize = StandardWindowSizing.contentSize(preferred: CGSize(width: 900, height: 680),
            visibleFrames: screens.map(\.visibleFrame))
        let initialFrameSize = window.frame.size
        var transitions = 0
        for _ in 0..<4 {
            for screen in screens {
                let bounds = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: bounds.midX - window.frame.width / 2,
                                              y: bounds.midY - window.frame.height / 2))
                precondition(window.screen == screen, "The test window must actually reach the destination display")
                let count = window.sizeWrites
                for _ in 0..<12 { NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window) }
                precondition(window.sizeWrites == count, "Screen notifications must never resize synchronously")
                spin(.eventTracking, seconds: 0.2)
                precondition(window.sizeWrites == count, "No resizing inside the drag tracking loop")
                spin()
                window.contentView?.layoutSubtreeIfNeeded()
                let expected = sharedSize
                let content = window.contentRect(forFrameRect: window.frame).size
                precondition(abs(content.width - expected.width) < 1 && abs(content.height - expected.height) < 1)
                precondition(window.sizeWrites <= count + 1, "Coalesced notifications must cause at most one resize")
                precondition(window.frame.width * window.frame.height / (bounds.width * bounds.height) <= 0.35)
                precondition(window.frame.size == initialFrameSize, "Monitor changes must preserve the same window dimensions")
                let settled = window.sizeWrites
                for _ in 0..<12 { NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window) }
                spin()
                precondition(window.sizeWrites == settled, "An unchanged target size must not restart layout")
                transitions += 1
            }
        }
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 50, y: window.frame.minY + 25))
        let dragged = window.frame
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        spin()
        precondition(window.frame == dragged, "Refocusing must preserve the user's position")
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
        spin()
        let reopened = StandardWindowSizing.openingScreen!.visibleFrame
        precondition(abs(window.frame.midX - reopened.midX) < 1 && abs(window.frame.midY - reopened.midY) < 1)
        window.contentView = nil
        print("PASS: 5 screen sizes; \(transitions) transitions across \(screens.count) displays; no resize during tracking; same size on every monitor; coalesced, idempotent sizing; draggable; no fullscreen; centered reopen")
    }
}
