import SwiftUI
import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated { Store.shared.applyAppearance() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Store.shared.shutdown() }
    }

    /// .torrent files opened from Finder and magnet: links clicked anywhere.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            let store = Store.shared
            for u in urls {
                if u.isFileURL, u.pathExtension.lowercased() == "torrent", let d = try? Data(contentsOf: u) {
                    store.addTorrent(d)
                } else if u.scheme?.lowercased() == "magnet" {
                    store.add(uris: [u.absoluteString])
                } else if u.scheme?.lowercased() == "swiftdm" {
                    handleAppLink(u)
                }
            }
        }
    }

    /// Links from the Chrome extension:
    ///   swiftdm://reveal?gid=…  → show the file in Finder
    ///   swiftdm://open?gid=…    → open the finished file
    ///   swiftdm://show          → bring the window forward
    @MainActor private func handleAppLink(_ u: URL) {
        let store = Store.shared
        let gid = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "gid" }?.value
        switch u.host {
        case "reveal", "open":
            Task {
                if store.task(gid) == nil { await store.refresh() }
                guard let t = store.task(gid) else { return }
                if u.host == "open" { store.open(t) } else { store.reveal(t) }
            }
        case "settings":
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
            NotificationCenter.default.post(name: .openSettingsPage, object: u.pathComponents.dropFirst().first)
        default:
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
        }
    }

    // Show banners even when the app is in front
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Clicking a "Download complete" notification reveals the file
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let p = response.notification.request.content.userInfo["path"] as? String {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
        completionHandler()
    }
}

@main
struct SwiftDMApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var store = Store.shared

    init() {
        Store.shared.start()
    }

    var body: some Scene {
        Window("Swift DM", id: "main") {
            MainView().environmentObject(store)
        }
        .defaultSize(width: 980, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download…") { NotificationCenter.default.post(name: .newTask, object: nil) }
                    .keyboardShortcut("n")
                Button("Open Torrent File…") { NotificationCenter.default.post(name: .openTorrent, object: nil) }
                    .keyboardShortcut("o")
            }
            CommandMenu("Downloads") {
                Button("Resume All") { store.resumeAll() }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Pause All") { store.pauseAll() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button(store.limitMode ? "Turn Off Speed Limit" : "Turn On Speed Limit") { store.toggleLimitMode() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Clear Finished") { store.purge() }
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(store)
        }
    }
}

extension Notification.Name {
    static let newTask = Notification.Name("sdm.newTask")
    static let openTorrent = Notification.Name("sdm.openTorrent")
    /// Shows the Settings page inside the main window (object: optional tab name).
    static let openSettingsPage = Notification.Name("sdm.openSettingsPage")
}

struct MenuBarLabel: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if Prefs.menuBarSpeed && store.downSpeed > 0 {
            Text("↓ \(Fmt.compactSpeed(store.downSpeed))").monospacedDigit()
        } else {
            Image(systemName: store.limitMode ? "tortoise" : "arrow.down.circle")
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.speed(store.downSpeed))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                    .monospacedDigit()
                Spacer()
                Text("↑ \(Fmt.speed(store.upSpeed))").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            SpeedGraph(samples: store.speedHistory, lineWidth: 1.5).frame(height: 40)
            let live = store.tasks.filter(\.isLive)
            if live.isEmpty {
                Text("No active downloads").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
            } else {
                ForEach(live.prefix(6)) { t in
                    HStack(spacing: 10) {
                        KindIcon(kind: FileKind(t), size: 30)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            GradientProgress(value: t.progress, style: Theme.gradient(for: t), height: 4,
                                             glow: t.status == "active" ? Theme.blue : .clear)
                            Text(t.status == "active"
                                 ? "\(Int(t.progress * 100))% · \(Fmt.speed(t.speed))\(t.eta.map { " · " + Fmt.time($0) } ?? "")"
                                 : "\(t.status == "paused" ? "Paused" : "Queued") · \(Int(t.progress * 100))%")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
                if live.count > 6 { Text("+\(live.count - 6) more").font(.caption).foregroundStyle(.secondary) }
            }
            Divider()
            Button { show(); NotificationCenter.default.post(name: .newTask, object: nil) } label: {
                Label("New Download…", systemImage: "plus")
            }
            Button { show(); NotificationCenter.default.post(name: .openTorrent, object: nil) } label: {
                Label("Open Torrent File…", systemImage: "doc")
            }
            Button { store.toggleLimitMode() } label: {
                Label(store.limitMode ? "Speed limit is on" : "Speed limit is off", systemImage: store.limitMode ? "tortoise.fill" : "hare")
            }
            Divider()
            HStack {
                Button("Open Swift DM") { show() }
                Spacer()
                Button { store.pauseAll() } label: { Image(systemName: "pause.fill") }.help("Pause all")
                Button { store.resumeAll() } label: { Image(systemName: "play.fill") }.help("Resume all")
                SettingsLink { Image(systemName: "gearshape") }.help("Settings")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quit")
            }
        }
        .buttonStyle(.borderless)
        .padding(14)
        .frame(width: 320)
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
