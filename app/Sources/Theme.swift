import SwiftUI

/// Colours, gradients and small reusable pieces for the redesigned UI.
enum Theme {
    static let blue = Color(red: 0.25, green: 0.52, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.36, blue: 1.0)

    static let green = Color(red: 0.13, green: 0.77, blue: 0.47)
    static let teal = Color(red: 0.1, green: 0.7, blue: 0.8)
    static let accent = LinearGradient(colors: [blue, violet], startPoint: .leading, endPoint: .trailing)
    static let seeding = LinearGradient(colors: [Color(red: 0.13, green: 0.77, blue: 0.47), .teal], startPoint: .leading, endPoint: .trailing)
    static let paused = LinearGradient(colors: [.orange, Color(red: 1, green: 0.78, blue: 0.2)], startPoint: .leading, endPoint: .trailing)
    static let failed = LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
    static let done = LinearGradient(colors: [Color(red: 0.13, green: 0.77, blue: 0.47), Color(red: 0.13, green: 0.77, blue: 0.47)], startPoint: .leading, endPoint: .trailing)

    static func gradient(for t: DLTask) -> LinearGradient {
        switch t.status {
        case "paused", "waiting": return paused
        case "error", "removed": return failed
        case "complete": return done
        default: return t.isSeeding ? seeding : accent
        }
    }

    static func status(for t: DLTask) -> (String, Color) {
        switch t.status {
        case "active": return t.isSeeding ? ("Seeding", .green) : t.isMetadata ? ("Fetching info", violet) : ("Downloading", blue)
        case "waiting": return ("Queued", .orange)
        case "paused": return ("Paused", .orange)
        case "complete": return ("Done", .green)
        case "removed": return ("Stopped", .secondary)
        case "error": return ("Failed", .red)
        default: return (t.status.capitalized, .secondary)
        }
    }
}

/// What kind of file a download is, for the coloured icon.
enum FileKind {
    case video, audio, image, archive, document, app, torrent, code, other

    init(_ t: DLTask) {
        if t.isTorrent || t.isMetadata, t.files.count != 1 { self = .torrent; return }
        switch (t.name as NSString).pathExtension.lowercased() {
        case "mp4", "m4v", "mkv", "webm", "mov", "avi", "flv", "wmv", "ts", "mpg", "mpeg": self = .video
        case "mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "aiff": self = .audio
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg", "bmp", "tiff", "avif": self = .image
        case "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz": self = .archive
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "epub", "csv", "md", "pages", "key", "numbers": self = .document
        case "dmg", "pkg", "app", "exe", "msi", "apk", "deb", "rpm", "iso", "img", "appimage": self = .app
        case "torrent": self = .torrent
        case "js", "json", "py", "swift", "html", "css", "xml", "yml", "yaml", "sh": self = .code
        default: self = t.isTorrent ? .torrent : .other
        }
    }

    var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .image: return "photo.fill"
        case .archive: return "archivebox.fill"
        case .document: return "doc.text.fill"
        case .app: return "shippingbox.fill"
        case .torrent: return "point.3.filled.connected.trianglepath.dotted"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return Color(red: 0.62, green: 0.34, blue: 1.0)
        case .audio: return Color(red: 1.0, green: 0.33, blue: 0.55)
        case .image: return Color(red: 0.15, green: 0.75, blue: 0.5)
        case .archive: return Color(red: 1.0, green: 0.6, blue: 0.15)
        case .document: return Color(red: 0.2, green: 0.55, blue: 1.0)
        case .app: return Color(red: 0.42, green: 0.47, blue: 0.56)
        case .torrent: return Color(red: 0.1, green: 0.7, blue: 0.75)
        case .code: return Color(red: 0.95, green: 0.4, blue: 0.3)
        case .other: return Color(red: 0.5, green: 0.55, blue: 0.65)
        }
    }
}

struct KindIcon: View {
    let kind: FileKind
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: [kind.color, kind.color.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

struct GradientProgress: View {
    let value: Double
    var style: LinearGradient = Theme.accent
    var height: CGFloat = 6
    var glow: Color = Theme.blue

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(style)
                    .frame(width: value > 0 ? max(height, g.size.width * min(1, value)) : 0)
            }
        }
        .frame(height: height)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Smooth area chart of recent download speed.
/// Built from Shapes (vector paths) instead of Canvas: Canvas re-rasterises into new
/// GPU buffers on every update, which cost ~50 MB while downloading.
struct SpeedGraph: View {
    let samples: [Int64]
    var lineWidth: CGFloat = 2
    var colors: [Color] = [Theme.blue, Theme.violet]

    var body: some View {
        ZStack {
            SpeedCurve(samples: samples, inset: lineWidth, closed: true)
                .fill(LinearGradient(colors: [colors[0].opacity(0.35), colors[colors.count - 1].opacity(0.02)], startPoint: .top, endPoint: .bottom))
            SpeedCurve(samples: samples, inset: lineWidth, closed: false)
                .stroke(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SpeedCurve: Shape {
    let samples: [Int64]
    let inset: CGFloat
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard samples.count > 1 else { return p }
        let peak = max(Double(samples.max() ?? 1), 64 * 1024)
        let stepX = rect.width / CGFloat(samples.count - 1)
        let pts = samples.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: rect.height - CGFloat(Double(v) / peak) * (rect.height - inset * 2) - inset)
        }
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: pts[pts.count - 1])
        if closed {
            p.addLine(to: CGPoint(x: rect.width, y: rect.height))
            p.addLine(to: CGPoint(x: 0, y: rect.height))
            p.closeSubpath()
        }
        return p
    }
}

struct CircleButton: View {
    let symbol: String
    let help: String
    var tint: Color = .primary
    let action: () -> Void
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(hover ? tint : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hover ? 0.12 : 0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
    }
}
