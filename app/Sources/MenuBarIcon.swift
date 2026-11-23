import AppKit

/// MenuBarExtra ignores the SwiftUI font on a symbol label. Give it a
/// template with an explicit point size, retaining sharp Retina rendering.
enum MenuBarIcon {
    static let download = make("arrow.down.circle")
    static let limited = make("tortoise")

    private static func make(_ name: String) -> NSImage {
        let pointSize: CGFloat = 22
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Swift DM")?
            .withSymbolConfiguration(configuration) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        let scale = pointSize / max(symbol.size.width, symbol.size.height)
        let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        // Wrap the symbol in an ordinary image so the status button uses
        // this size instead of substituting the system's 15-point symbol.
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
