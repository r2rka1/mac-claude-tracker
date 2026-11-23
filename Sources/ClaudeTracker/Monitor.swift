import Foundation

/// Samples system stats and Claude sessions on a background queue and publishes on main.
final class Monitor: ObservableObject {
    @Published var system = SystemSnapshot()
    @Published var sessions: [SessionInfo] = []
    @Published var cpuHistory: [Double] = []
    @Published var updatedAt = Date()

    static let interval: TimeInterval = 2
    private let queue = DispatchQueue(label: "claudetracker.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let scanner = ClaudeScanner()
    private var lastTicks: CPUTicks?

    var busyCount: Int { sessions.filter(\.isBusy).count }

    var menuTitle: String {
        "C\(Fmt.pct(system.cpu)) M\(Fmt.pct(system.memFraction)) ✳\(busyCount)/\(sessions.count)"
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// One full sample. Runs on the monitor queue (or directly, for --dump).
    func sample() -> (SystemSnapshot, [SessionInfo]) {
        var snap = SystemSnapshot()
        if let ticks = SystemStats.cpuTicks() {
            if let last = lastTicks {
                (snap.cpu, snap.cpuUser, snap.cpuSystem) = SystemStats.cpuUsage(from: last, to: ticks)
            }
            lastTicks = ticks
        }
        snap.load = SystemStats.loadAverage()
        snap.memUsed = SystemStats.memoryUsed()
        snap.swapUsed = SystemStats.swapUsed()
        (snap.diskFree, snap.diskTotal) = SystemStats.disk()

        let procs = SystemStats.processes()
        snap.procCount = procs.count
        snap.topCPU = Array(procs.sorted { $0.cpu > $1.cpu }.prefix(6))
        snap.topMem = Array(procs.sorted { $0.rssBytes > $1.rssBytes }.prefix(6))

        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        var sessions = scanner.scan()
        for i in sessions.indices {
            if let p = byPid[sessions[i].pid] {
                sessions[i].cpu = p.cpu
                sessions[i].rssBytes = p.rssBytes
            }
        }
        return (snap, sessions)
    }

    private func tick() {
        let (snap, sessions) = sample()
        DispatchQueue.main.async {
            self.system = snap
            self.sessions = sessions
            self.cpuHistory.append(snap.cpu)
            if self.cpuHistory.count > 60 { self.cpuHistory.removeFirst(self.cpuHistory.count - 60) }
            self.updatedAt = Date()
        }
    }
}
