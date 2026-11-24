import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            dump()
        } else if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
            Mascot.writeIcon(.tracker, to: args[i + 1])
        } else if let i = args.firstIndex(of: "--render-store"), i + 1 < args.count {
            StoreShots.render(into: args[i + 1])
        } else if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            render(to: args[i + 1])
        } else {
            ClaudeTrackerApp.main()
        }
    }

    /// A monitor filled for rendering: made-up data with `--demo`, a live sample otherwise.
    @MainActor static func renderMonitor(demo: Bool, store: Bool) -> Monitor {
        let m = Monitor()
        if demo {
            (m.system, m.sessions) = Demo.sample()
        } else {
            _ = m.sample()
            Thread.sleep(forTimeInterval: 0.5)
            (m.system, m.sessions) = m.sample()
        }
        m.cpuHistory = (0..<60).map { (i: Int) -> Double in
            let t = Double(i)
            let slow: Double = 0.14 * sin(t / 5)
            let fast: Double = 0.08 * sin(t / 1.7)
            return 0.28 + slow + fast
        }
        m.needsAccess = false
        if store { m.system.procDetail = false }  // the App Store build has no process lists
        return m
    }

    /// Renders the panel to a PNG offscreen. `--demo` uses made-up data (for screenshots that
    /// are safe to share), `--dark` uses the dark appearance, `--store` shows the App Store build.
    @MainActor static func render(to path: String) {
        let args = CommandLine.arguments
        let m = renderMonitor(demo: args.contains("--demo"), store: args.contains("--store"))
        let view = DashboardView(inWindow: false).environmentObject(m).tint(Mascot.tint)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        png(of: view, size: nil, dark: args.contains("--dark"), to: path)
    }

    /// Draws a SwiftUI view offscreen at 2x. A nil size means the view's own fitting size.
    @MainActor static func png(of view: some View, size: CGSize?, dark: Bool, to path: String) {
        _ = NSApplication.shared
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let size = host.bounds.size
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return print("render failed") }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return print("render failed") }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Prints one sample as text; used to check the data pipeline without the UI.
    static func dump() {
        let m = Monitor()
        _ = m.sample()
        Thread.sleep(forTimeInterval: 0.5)
        let (s, sessions) = m.sample()
        print("CPU \(Fmt.pct(s.cpu)) load \(s.load)  MEM \(Fmt.bytes(s.memUsed))/\(Fmt.bytes(s.memTotal)) swap \(Fmt.bytes(s.swapUsed))")
        print("DSK \(Fmt.bytes(s.diskFree)) free of \(Fmt.bytes(s.diskTotal))  procs \(s.procCount)")
        print("top cpu: " + s.topCPU.map { "\($0.name) \($0.cpu)%" }.joined(separator: ", "))
        print("top mem: " + s.topMem.map { "\($0.name) \(Fmt.bytes($0.rssBytes))" }.joined(separator: ", "))
        for x in sessions {
            print("[\(x.status)] \(x.project) pid \(x.pid) · \(x.title ?? "-") · ctx \(x.contextTokens ?? 0) · \(Fmt.age(x.lastActive))")
            print("    activity: \(x.activity ?? "-")")
            print("    prompt:   \(x.lastPrompt ?? "-")")
            print("    text:     \((x.lastText ?? "-").prefix(120))")
            for a in x.subagents {
                print("    ↳ \(a.type) \(a.description) · \(a.activity) · \(Fmt.age(a.lastActive))")
            }
        }
    }
}

struct ClaudeTrackerApp: App {
    @StateObject private var monitor: Monitor = {
        let m = Monitor()
        m.start()
        return m
    }()

    var body: some Scene {
        MenuBarExtra {
            DashboardView(inWindow: false).environmentObject(monitor).tint(Mascot.tint)
        } label: {
            Text(monitor.menuTitle)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Tracker", id: "main") {
            DashboardView(inWindow: true).environmentObject(monitor).tint(Mascot.tint)
        }
        .defaultSize(width: 480, height: 720)
    }
}
