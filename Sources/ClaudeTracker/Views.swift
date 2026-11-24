import ServiceManagement
import SwiftUI

private let mono = Font.system(size: 11, design: .monospaced)
private let monoSmall = Font.system(size: 10, design: .monospaced)

private func level(_ f: Double) -> Color {
    f >= 0.9 ? .red : f >= 0.75 ? .orange : .green
}

struct DashboardView: View {
    @EnvironmentObject var monitor: Monitor
    @Environment(\.openWindow) private var openWindow
    let inWindow: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SystemSection(s: monitor.system, history: monitor.cpuHistory)
            Divider()
            ProcessSection(s: monitor.system)
            Divider()
            sessionsHeader
            if inWindow {
                ScrollView { SessionList(sessions: monitor.sessions) }
            } else {
                ViewThatFits(in: .vertical) {
                    SessionList(sessions: monitor.sessions)
                    ScrollView { SessionList(sessions: monitor.sessions) }
                }
                .frame(maxHeight: 440)
            }
            Divider()
            Footer(inWindow: inWindow) {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .padding(10)
        .frame(width: inWindow ? nil : 470)
        .frame(minWidth: inWindow ? 420 : nil, maxHeight: inWindow ? .infinity : nil, alignment: .top)
    }

    private var sessionsHeader: some View {
        HStack {
            Image(nsImage: Mascot.image(size: 16)).interpolation(.none)
            Text("CLAUDE").font(mono.bold())
            Text("\(monitor.busyCount) busy · \(monitor.sessions.count - monitor.busyCount) idle")
                .font(mono).foregroundStyle(.secondary)
            Spacer()
            let agents = monitor.sessions.reduce(0) { $0 + $1.subagents.count }
            if agents > 0 {
                Text("\(agents) subagent\(agents == 1 ? "" : "s")").font(mono).foregroundStyle(.orange)
            }
        }
    }
}

// MARK: system

private struct SystemSection: View {
    let s: SystemSnapshot
    let history: [Double]

    var body: some View {
        VStack(spacing: 4) {
            row("CPU", s.cpu) {
                Sparkline(values: history).frame(width: 70, height: 12)
                Text(String(format: "load %.1f %.1f %.1f", s.load[0], s.load[1], s.load[2]))
            }
            row("MEM", s.memFraction) {
                Text("\(Fmt.bytes(s.memUsed))/\(Fmt.bytes(s.memTotal))")
                Text("swap \(Fmt.bytes(s.swapUsed))")
            }
            row("DSK", s.diskFraction) {
                Text("\(Fmt.bytes(s.diskFree)) free of \(Fmt.bytes(s.diskTotal))")
            }
        }
    }

    private func row<Detail: View>(_ label: String, _ value: Double, @ViewBuilder detail: () -> Detail)
        -> some View
    {
        HStack(spacing: 6) {
            Text(label).font(mono.bold()).frame(width: 28, alignment: .leading)
            Text(Fmt.pct(value)).font(mono).frame(width: 34, alignment: .trailing)
            Bar(value: value).frame(width: 110)
            Spacer(minLength: 4)
            detail().font(monoSmall).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct Bar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.12))
                Rectangle().fill(level(value))
                    .frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { g in
            Path { p in
                guard values.count > 1 else { return }
                let step = g.size.width / CGFloat(59)
                let x0 = g.size.width - step * CGFloat(values.count - 1)
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(
                        x: x0 + step * CGFloat(i),
                        y: g.size.height * (1 - CGFloat(min(max(v, 0), 1))))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.accentColor, lineWidth: 1)
        }
    }
}

private struct ProcessSection: View {
    let s: SystemSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column("TOP CPU", s.topCPU) { String(format: "%.0f%%", $0.cpu) }
            column("TOP MEM · \(s.procCount) procs", s.topMem) { Fmt.bytes($0.rssBytes) }
        }
    }

    private func column(_ title: String, _ procs: [ProcInfo], value: @escaping (ProcInfo) -> String)
        -> some View
    {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(monoSmall.bold()).foregroundStyle(.secondary)
            ForEach(procs) { p in
                HStack(spacing: 4) {
                    Text(p.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(value(p)).foregroundStyle(.secondary)
                }
                .font(monoSmall)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: claude sessions

private struct SessionList: View {
    let sessions: [SessionInfo]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sessions.isEmpty {
                Text("no active Claude sessions").font(mono).foregroundStyle(.secondary)
            }
            ForEach(sessions) { SessionRow(s: $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionRow: View {
    let s: SessionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(s.isBusy ? Color.green : s.status == "idle" ? Color.gray : Color.orange)
                    .frame(width: 7, height: 7)
                Text(s.project).font(mono.bold()).lineLimit(1)
                if let title = s.title {
                    Text(title).font(mono).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(meta).font(monoSmall).foregroundStyle(.secondary).lineLimit(1)
                    .layoutPriority(1)
            }
            .help("\(s.name) · pid \(s.pid) · \(s.cwd)\n\(s.model ?? "") · \(Fmt.bytes(s.rssBytes)) RAM")

            if s.isBusy, let a = s.activity {
                Text(a).font(monoSmall).foregroundStyle(.green).lineLimit(1).padding(.leading, 12)
            }
            if let p = s.lastPrompt, s.isBusy {
                Text("› " + p).font(monoSmall).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.leading, 12)
            }
            if let t = s.lastText {
                Text(t).font(monoSmall).foregroundStyle(s.isBusy ? .primary : .secondary)
                    .lineLimit(s.isBusy ? 2 : 1).padding(.leading, 12)
            }
            ForEach(s.subagents) { a in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text("↳ \(a.type)").foregroundStyle(.orange)
                        Text(a.description).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.age(a.lastActive)).foregroundStyle(.secondary)
                    }
                    Text(a.activity).foregroundStyle(.green).lineLimit(1).padding(.leading, 12)
                    if let t = a.lastText {
                        Text(t).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 12)
                    }
                }
                .font(monoSmall)
                .padding(.leading, 12)
            }
        }
    }

    private var meta: String {
        var parts: [String] = [s.isBusy ? "busy" : s.status]
        if let c = s.contextTokens { parts.append("ctx " + Fmt.tokens(c)) }
        if s.cpu >= 1 { parts.append(String(format: "%.0f%%", s.cpu)) }
        parts.append(Fmt.age(s.lastActive))
        return parts.joined(separator: " · ")
    }
}

// MARK: footer

private struct Footer: View {
    let inWindow: Bool
    let openMain: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Spacer()
            if !inWindow { Button("Window", action: openMain) }
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.system(size: 11))
        .controlSize(.small)
    }
}
