import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            dump()
        } else if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            render(to: args[i + 1])
        } else {
            ClaudeTrackerApp.main()
        }
    }

    /// Renders the panel to a PNG offscreen; used to check layout without screen access.
    @MainActor static func render(to path: String) {
        let m = Monitor()
        _ = m.sample()
        Thread.sleep(forTimeInterval: 0.5)
        (m.system, m.sessions) = m.sample()
        m.cpuHistory = (0..<40).map { 0.3 + 0.25 * sin(Double($0) / 4) }
        let view = DashboardView(inWindow: false).environmentObject(m)
            .background(Color(nsColor: .windowBackgroundColor))
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let tiff = r.nsImage?.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return print("render failed") }
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
            DashboardView(inWindow: false).environmentObject(monitor)
        } label: {
            Text(monitor.menuTitle)
        }
        .menuBarExtraStyle(.window)

        Window("Claude Tracker", id: "main") {
            DashboardView(inWindow: true).environmentObject(monitor)
        }
        .defaultSize(width: 480, height: 720)
    }
}
