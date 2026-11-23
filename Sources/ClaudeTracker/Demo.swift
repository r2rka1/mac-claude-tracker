import Foundation

/// Made-up data for screenshots, so nothing from the real machine ends up in an image.
enum Demo {
    static func sample() -> (SystemSnapshot, [SessionInfo]) {
        let gb: UInt64 = 1_073_741_824
        let mb: UInt64 = 1_048_576
        var s = SystemSnapshot()
        s.cpu = 0.37
        s.load = [3.1, 2.8, 2.6]
        s.memTotal = 32 * gb
        s.memUsed = 19 * gb + 600 * mb
        s.swapUsed = 1 * gb + 200 * mb
        s.diskTotal = 994 * gb
        s.diskFree = 412 * gb
        s.procCount = 612
        let cpu: [(String, Double)] = [
            ("node", 84), ("claude", 41), ("WindowServer", 22), ("swift-frontend", 18),
            ("Safari", 9), ("claude", 6),
        ]
        let mem: [(String, UInt64)] = [
            ("Xcode", 2400), ("Safari", 1300), ("claude", 640), ("node", 590), ("claude", 470),
            ("Docker", 420),
        ]
        s.topCPU = cpu.enumerated().map { ProcInfo(pid: 100 + $0, cpu: $1.1, rssBytes: 0, name: $1.0) }
        s.topMem = mem.enumerated().map {
            ProcInfo(pid: 200 + $0, cpu: 0, rssBytes: $1.1 * mb, name: $1.0)
        }

        let now = Date()
        func session(
            _ project: String, _ title: String, busy: Bool, ctx: Int, age: TimeInterval,
            cpu: Double = 0, activity: String? = nil, prompt: String? = nil, text: String,
            subagents: [SubagentInfo] = []
        ) -> SessionInfo {
            var x = SessionInfo(
                id: project + title, pid: 1, name: project, cwd: "/Users/me/Projects/" + project,
                status: busy ? "busy" : "idle", kind: "interactive", startedAt: now)
            x.title = title
            x.contextTokens = ctx
            x.lastActive = now.addingTimeInterval(-age)
            x.cpu = cpu
            x.activity = activity
            x.lastPrompt = prompt
            x.lastText = text
            x.subagents = subagents
            return x
        }
        let sessions = [
            session(
                "shop-api", "Checkout retry handling", busy: true, ctx: 148_000, age: 3, cpu: 41,
                activity: "▶ Bash: Run the payment integration tests",
                prompt: "retries double-charge when the gateway times out, find out why and fix it",
                text: "The retry reuses the request without its idempotency key. Adding the key to the retry path, then running the integration tests.",
                subagents: [
                    SubagentInfo(
                        id: "a1", type: "Explore", description: "Map every caller of the charge client",
                        activity: "▶ Grep: chargeClient\\.(create|capture)",
                        lastText: "Found 7 call sites so far, 2 outside the payments module.",
                        lastActive: now.addingTimeInterval(-2)),
                    SubagentInfo(
                        id: "a2", type: "general-purpose", description: "Check gateway docs on idempotency",
                        activity: "… thinking", lastText: nil, lastActive: now.addingTimeInterval(-9)),
                ]),
            session(
                "web-dashboard", "Dark mode for charts", busy: true, ctx: 61_000, age: 1, cpu: 6,
                activity: "✎ writing",
                prompt: "the chart colors are unreadable in dark mode",
                text: "Three series fail contrast on the dark surface. Switching them to the lighter steps of the same hues."),
            session(
                "infra", "Staging deploy pipeline", busy: false, ctx: 203_000, age: 4 * 60,
                text: "The pipeline is green: staging now deploys on every merge to main, in about 4 minutes."),
            session(
                "docs-site", "Search index rebuild", busy: false, ctx: 37_000, age: 26 * 60,
                text: "Search works again. The index was built before the pages were generated, so it was empty."),
            session(
                "notes", "Weekly summary draft", busy: false, ctx: 12_000, age: 3 * 3600,
                text: "Draft is in summary.md, five bullet points per project."),
        ]
        return (s, sessions)
    }
}
