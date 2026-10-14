// Render SF Symbols as template PNGs for the menu picture (scripts/render_menu.sh):
//   swift symbols.swift OUTDIR POINTSIZE NAME...
// Each NAME is drawn black on transparent at 3x, and OUTDIR/symbols.js records
// its size in points and the PNG as a data: URL, so the page can tint it with
// a CSS mask in the menu's colors. A name macOS doesn't know is skipped.
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let size = Double(args[2]) else {
    FileHandle.standardError.write("usage: symbols.swift OUTDIR POINTSIZE NAME...\n".data(using: .utf8)!)
    exit(2)
}
let out = URL(fileURLWithPath: args[1])
let scale = 3.0
var sizes: [String] = []

for name in args.dropFirst(3) {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let image = base.withSymbolConfiguration(config) else {
        FileHandle.standardError.write("symbols.swift: no symbol \(name)\n".data(using: .utf8)!)
        continue
    }
    let w = image.size.width, h = image.size.height
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((w * scale).rounded(.up)),
                                     pixelsHigh: Int((h * scale).rounded(.up)), bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
    NSColor.black.set()
    NSRect(x: 0, y: 0, width: w, height: h).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    // Inline, as a data: URL: Chrome won't apply a CSS mask from a file:// URL.
    sizes.append(String(format: "\"%@\":[%.2f,%.2f,\"data:image/png;base64,%@\"]",
                        name, w, h, png.base64EncodedString()))
}

let js = "window.SYMBOLS = {" + sizes.joined(separator: ",") + "};\n"
try js.write(to: out.appendingPathComponent("symbols.js"), atomically: true, encoding: .utf8)
