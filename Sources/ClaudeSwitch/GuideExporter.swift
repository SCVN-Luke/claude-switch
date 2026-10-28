import AppKit
import ClaudeSwitchCore
import SwiftUI

/// Debug aid: `ClaudeSwitch --export-guide <dir>` writes every Guide page, in every language,
/// as `<dir>/<lang>-step<N>.png`, then quits. Used to check the red highlights without a screen.
@MainActor
enum GuideExporter {
    static var outputDir: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--export-guide"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for lang in AppLanguage.allCases {
            for step in GuideStep.all {
                let page = GuideStepPage(step: step, language: lang)
                    .padding(20)
                    .background(Color(nsColor: .windowBackgroundColor))
                let url = dir.appendingPathComponent("\(lang.rawValue)-step\(step.id).png")
                if let png = render(page) {
                    try? png.write(to: url)
                    print("wrote \(url.path)")
                } else {
                    print("FAILED \(url.lastPathComponent)")
                }
            }
        }
    }

    /// Renders through a real (offscreen) window so AppKit-backed controls draw too.
    private static func render<V: View>(_ view: V) -> Data? {
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        defer { window.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
