import Foundation

/// A UserDefaults-backed static preference.
@propertyWrapper
struct Pref<T> {
    let key: String
    let defaultValue: T

    init(wrappedValue: T, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: key) as? T ?? defaultValue }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

enum Prefs {
    static let defaultDownloads = (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
    static let chromeUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"
    static let userAgentPresets: [(String, String)] = [
        ("aria2", "aria2/1.37.0"),
        ("Chrome", chromeUA),
        ("Transmission", "Transmission/4.0.6"),
        ("qBittorrent", "qBittorrent/5.0.0"),
    ]

    // MARK: General
    @Pref("theme") static var theme = "system"                 // system | light | dark
    @Pref("showInDock") static var showInDock = true
    @Pref("menuBarSpeed") static var menuBarSpeed = true
    @Pref("dockProgress") static var dockProgress = true
    @Pref("autoResumeAll") static var autoResumeAll = false
    @Pref("showDownloadingAfterAdd") static var showDownloadingAfterAdd = true
    @Pref("confirmDelete") static var confirmDelete = true
    @Pref("notify") static var notify = true
    @Pref("preventSleep") static var preventSleep = true

    // MARK: Transfers
    @Pref("dir") static var downloadDir = defaultDownloads
    @Pref("recentDirs") static var recentDirs: [String] = []
    @Pref("maxConcurrent") static var maxConcurrent = 5
    @Pref("connections") static var connections = 16
    @Pref("downLimitKB") static var downLimitKB = 0
    @Pref("upLimitKB") static var upLimitKB = 0
    @Pref("limitMode") static var limitMode = false          // legacy on/off switch (migrated to speedMode)
    @Pref("speedMode") static var speedModeRaw = ""           // full | limited | quiet
    static var speedMode: String {
        get { speedModeRaw.isEmpty ? (limitMode ? "limited" : "full") : speedModeRaw }
        set { speedModeRaw = newValue }
    }
    static let quietDownKB = 256
    static let quietUpKB = 64
    static var effectiveDownKB: Int { speedMode == "limited" ? downLimitKB : speedMode == "quiet" ? quietDownKB : 0 }
    static var effectiveUpKB: Int { speedMode == "limited" ? upLimitKB : speedMode == "quiet" ? quietUpKB : 0 }

    // MARK: Dashboard
    @Pref("dashboardLayout") static var dashboardLayout: [String] = []
    @Pref("dashboardPreset") static var dashboardPreset = "Balanced"
    @Pref("dailyStats") static var dailyStatsRaw: [String: [Int64]] = [:]
    @Pref("userAgent") static var userAgent = chromeUA

    // MARK: BitTorrent
    @Pref("btSaveMetadata") static var btSaveMetadata = true
    @Pref("btAutoDownload") static var btAutoDownload = true  // start content after magnet metadata arrives
    @Pref("btForceEncryption") static var btForceEncryption = false
    @Pref("keepSeeding") static var keepSeeding = false
    @Pref("seedRatio") static var seedRatio = 1.0
    @Pref("seedMinutes") static var seedMinutes = 60
    @Pref("trackers") static var trackers = ""
    @Pref("autoSyncTrackers") static var autoSyncTrackers = true
    @Pref("lastTrackerSync") static var lastTrackerSync = 0.0

    // MARK: Network
    @Pref("proxyEnabled") static var proxyEnabled = false
    @Pref("proxyServer") static var proxyServer = ""
    @Pref("proxyBypass") static var proxyBypass = ""
    @Pref("rpcPort") static var rpcPort = 16888
    @Pref("btPort") static var btPort = 21301
    @Pref("dhtPort") static var dhtPort = 26701

    static var secret: String {
        get {
            if let s = UserDefaults.standard.string(forKey: "rpcSecret"), !s.isEmpty { return s }
            let s = newSecret()
            UserDefaults.standard.set(s, forKey: "rpcSecret")
            return s
        }
        set { UserDefaults.standard.set(newValue, forKey: "rpcSecret") }
    }

    static func newSecret() -> String {
        (0..<24).map { _ in String("abcdefghijkmnpqrstuvwxyz23456789".randomElement()!) }.joined()
    }

    static var trackerList: [String] {
        trackers.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func rememberDir(_ dir: String) {
        var list = recentDirs.filter { $0 != dir }
        list.insert(dir, at: 0)
        recentDirs = Array(list.prefix(6))
    }

    /// aria2 options that can change while the engine runs (applied with aria2.changeGlobalOption).
    static var liveOptions: [String: String] {
        var o: [String: String] = [
            "dir": downloadDir,
            "max-concurrent-downloads": "\(maxConcurrent)",
            "split": "\(connections)",
            "max-connection-per-server": "\(connections)",
            "max-overall-download-limit": "\(effectiveDownKB)K",
            "max-overall-upload-limit": "\(effectiveUpKB)K",
            "user-agent": userAgent,
            "all-proxy": proxyEnabled ? proxyServer : "",
            "no-proxy": proxyEnabled ? proxyBypass : "",
            "bt-tracker": trackerList.joined(separator: ","),
            "bt-save-metadata": btSaveMetadata ? "true" : "false",
            "pause-metadata": btAutoDownload ? "false" : "true",
            "bt-force-encryption": btForceEncryption ? "true" : "false",
        ]
        if keepSeeding {
            o["seed-ratio"] = "0.0"
            o["seed-time"] = "0"
        } else {
            o["seed-ratio"] = String(format: "%.1f", seedRatio)
            o["seed-time"] = "\(seedMinutes)"
        }
        // aria2: seed-ratio 0 with no seed-time seeds forever; seed-time 0 stops immediately.
        if keepSeeding { o.removeValue(forKey: "seed-time") }
        return o
    }
}
