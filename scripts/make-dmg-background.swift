// Renders the DMG window background (480×640 pt) at 1x and 2x into scripts/dmg-background.tiff.
// Layout must match the icon positions in make-dmg.sh: app (240,120), Applications (240,365), README (240,530).
// Usage: swift scripts/make-dmg-background.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let size = NSSize(width: 480, height: 640)

func render(scale: CGFloat) -> URL {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                               pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size  // keeps the 2x image at 480×640 points
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    // Flip so y grows downward, like Finder icon positions.
    let t = NSAffineTransform()
    t.translateX(by: 0, yBy: size.height)
    t.scaleX(by: 1, yBy: -1)
    t.concat()

    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()

    // Drop zone around Applications.
    let panel = NSRect(x: 90, y: 250, width: 300, height: 200)
    NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: panel, xRadius: 14, yRadius: 14).fill()

    // White arrow pointing down into the zone.
    NSColor.white.setFill()
    NSRect(x: 240 - 17, y: panel.minY, width: 34, height: 26).fill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 240 - 44, y: panel.minY + 24))
    head.line(to: NSPoint(x: 240 + 44, y: panel.minY + 24))
    head.line(to: NSPoint(x: 240, y: panel.minY + 64))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dmg-bg-\(Int(scale))x.png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    return url
}

let one = render(scale: 1), two = render(scale: 2)
let out = root.appendingPathComponent("dmg-background.tiff")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", one.path, two.path, "-out", out.path]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "tiffutil failed")
