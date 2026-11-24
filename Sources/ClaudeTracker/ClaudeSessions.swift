import Darwin
import Foundation

private typealias J = [String: Any]

struct SubagentInfo: Identifiable {
    let id: String
    let type: String
    let description: String
    let activity: String
    let lastText: String?
    let lastActive: Date
}

struct SessionInfo: Identifiable {
    let id: String
    let pid: Int
    let name: String
    let cwd: String
    let status: String          // "busy", "idle", ...
    let kind: String
    let startedAt: Date?
    var title: String?
    var lastPrompt: String?
    var activity: String?
    var lastText: String?
    var model: String?
    var contextTokens: Int?
    var lastActive: Date?
    var subagents: [SubagentInfo] = []
    var cpu: Double = 0
    var rssBytes: UInt64 = 0

    var isBusy: Bool { status == "busy" }
    var project: String { (cwd as NSString).lastPathComponent }
}

/// What the tail of a transcript says about the agent's current state.
struct TranscriptSummary {
    enum Kind { case toolUse, toolResult, thinking, text, prompt }
    var title: String?
    /// From the periodic `last-prompt` record, which can lag behind by a turn or more.
    var recordedPrompt: String?
    /// From the newest message the user actually sent, when it is within the parsed tail.
    var humanPrompt: String?
    var lastPrompt: String? { humanPrompt ?? recordedPrompt }
    var newest: Kind?
    var tool: String?
    var toolDetail: String?
    var lastText: String?
    var model: String?
    var contextTokens: Int?
    var ended = false

    var activity: String? {
        let t = [tool, toolDetail].compactMap { $0 }.joined(separator: ": ")
        switch newest {
        case .toolUse: return "▶ " + t
        case .toolResult: return "↩ " + (t.isEmpty ? "tool result" : t) + " → thinking"
        case .thinking: return "… thinking"
        case .text: return ended ? "✓ replied" : "✎ writing"
        case .prompt: return "… reading prompt"
        case nil: return nil
        }
    }
}

final class ClaudeScanner {
    private var root = URL(fileURLWithPath: "/nonexistent")
    private let fm = FileManager.default
    private var transcriptPaths: [String: URL] = [:]
    private var cache: [String: (mtime: Date, size: UInt64, summary: TranscriptSummary)] = [:]

    /// A subagent with no transcript writes for this long is treated as gone.
    /// CLAUDETRACKER_SUBAGENT_WINDOW (seconds) overrides it, for checking against old transcripts.
    private let subagentWindow: TimeInterval =
        ProcessInfo.processInfo.environment["CLAUDETRACKER_SUBAGENT_WINDOW"].flatMap(Double.init) ?? 15 * 60

    func scan() -> [SessionInfo] {
        guard let folder = ClaudeFolder.shared.root else { return [] }
        root = folder
        let dir = root.appendingPathComponent("sessions")
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return [] }
        var sessions: [SessionInfo] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                let o = (try? JSONSerialization.jsonObject(with: data)) as? J,
                let pid = o["pid"] as? Int, let sid = o["sessionId"] as? String,
                isAlive(pid)
            else { continue }
            let cwd = o["cwd"] as? String ?? ""
            var s = SessionInfo(
                id: sid, pid: pid,
                name: o["name"] as? String ?? String(sid.prefix(8)),
                cwd: cwd,
                status: o["status"] as? String ?? "?",
                kind: o["kind"] as? String ?? "",
                startedAt: (o["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) })
            if let ms = o["statusUpdatedAt"] as? Double {
                s.lastActive = Date(timeIntervalSince1970: ms / 1000)
            }
            if let path = transcriptPath(for: sid) {
                if let (sum, mtime) = summary(of: path, tail: 512 * 1024, wantMeta: true) {
                    s.title = sum.title
                    s.lastPrompt = sum.lastPrompt
                    s.activity = sum.activity
                    s.lastText = sum.lastText
                    s.model = sum.model
                    s.contextTokens = sum.contextTokens
                    s.lastActive = max(mtime, s.lastActive ?? mtime)
                }
                s.subagents = subagents(
                    in: path.deletingPathExtension().appendingPathComponent("subagents"))
            }
            sessions.append(s)
        }
        return sessions.sorted {
            if $0.isBusy != $1.isBusy { return $0.isBusy }
            return ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast)
        }
    }

    private func isAlive(_ pid: Int) -> Bool {
        // sysctl rather than kill(pid, 0): the sandbox refuses signals to other processes.
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        return sysctl(&mib, 4, &info, &size, nil, 0) == 0 && size > 0
    }

    private func transcriptPath(for sessionId: String) -> URL? {
        if let p = transcriptPaths[sessionId], fm.fileExists(atPath: p.path) { return p }
        let projects = root.appendingPathComponent("projects")
        guard let dirs = try? fm.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)
        else { return nil }
        for d in dirs {
            let candidate = d.appendingPathComponent(sessionId + ".jsonl")
            if fm.fileExists(atPath: candidate.path) {
                transcriptPaths[sessionId] = candidate
                return candidate
            }
        }
        return nil
    }

    private func subagents(in dir: URL) -> [SubagentInfo] {
        guard
            let files = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        let now = Date()
        var result: [SubagentInfo] = []
        for f in files where f.pathExtension == "jsonl" {
            guard
                let mtime = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate,
                now.timeIntervalSince(mtime) < subagentWindow
            else { continue }
            let metaURL = f.deletingPathExtension().appendingPathExtension("meta.json")
            let meta =
                (try? Data(contentsOf: metaURL)).flatMap {
                    (try? JSONSerialization.jsonObject(with: $0)) as? J
                } ?? [:]
            if meta["finished"] as? Bool == true { continue }
            guard let (sum, _) = summary(of: f, tail: 192 * 1024, wantMeta: false), !sum.ended
            else { continue }
            let id = f.deletingPathExtension().lastPathComponent
            result.append(
                SubagentInfo(
                    id: id,
                    type: meta["agentType"] as? String ?? "agent",
                    description: meta["description"] as? String ?? id,
                    activity: sum.activity ?? "starting",
                    lastText: sum.lastText,
                    lastActive: mtime))
        }
        return result.sorted { $0.lastActive > $1.lastActive }
    }

    // MARK: transcript tail parsing

    private func summary(of url: URL, tail: Int, wantMeta: Bool) -> (TranscriptSummary, Date)? {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
            let mtime = attrs[.modificationDate] as? Date,
            let size = (attrs[.size] as? NSNumber)?.uint64Value
        else { return nil }
        if let c = cache[url.path], c.mtime == mtime, c.size == size {
            return (c.summary, mtime)
        }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        // A single tool result can be larger than the tail, leaving nothing parseable;
        // widen once, and if that still fails keep showing the previous summary.
        var sum = TranscriptSummary()
        for bytes in [UInt64(tail), UInt64(tail) * 8] {
            let offset = size > bytes ? size - bytes : 0
            try? fh.seek(toOffset: offset)
            guard let data = try? fh.readToEnd() else { return nil }
            var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
            if offset > 0, !lines.isEmpty { lines.removeFirst() }  // partial line
            sum = Self.summarize(lines: lines, wantMeta: wantMeta)
            if sum.newest != nil || offset == 0 { break }
        }
        if sum.newest == nil, let previous = cache[url.path] {
            return (previous.summary, mtime)
        }
        cache[url.path] = (mtime, size, sum)
        return (sum, mtime)
    }

    private static let pAssistant = Data(#""type":"assistant""#.utf8)
    private static let pUser = Data(#""type":"user""#.utf8)
    private static let pTitle = Data(#""type":"ai-title""#.utf8)
    private static let pPrompt = Data(#""type":"last-prompt""#.utf8)

    static func summarize(lines: [Data], wantMeta: Bool) -> TranscriptSummary {
        var s = TranscriptSummary()
        var toolSearchClosed = false  // set once the walk passes a prompt: older tools are stale
        for line in lines.reversed() {
            let conv = line.range(of: pAssistant) != nil || line.range(of: pUser) != nil
            let meta =
                wantMeta && line.count < 8192
                && (line.range(of: pTitle) != nil || line.range(of: pPrompt) != nil)
            guard conv || meta,
                let o = (try? JSONSerialization.jsonObject(with: line)) as? J,
                let type = o["type"] as? String
            else { continue }

            switch type {
            case "ai-title":
                if s.title == nil { s.title = o["aiTitle"] as? String }
            case "last-prompt":
                if s.recordedPrompt == nil {
                    s.recordedPrompt = (o["lastPrompt"] as? String).map { clip(oneLine($0), 300) }
                }
            case "assistant":
                guard let m = o["message"] as? J, let content = m["content"] as? [J] else { continue }
                if s.model == nil { s.model = m["model"] as? String }
                if s.contextTokens == nil, let u = m["usage"] as? J {
                    let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"]
                        .reduce(0) { $0 + ((u[$1] as? Int) ?? 0) }
                    if n > 0 { s.contextTokens = n }
                }
                for block in content.reversed() {
                    switch block["type"] as? String {
                    case "tool_use":
                        if s.newest == nil { s.newest = .toolUse }
                        if s.tool == nil, !toolSearchClosed {
                            s.tool = block["name"] as? String
                            s.toolDetail = toolDetail(block["input"] as? J ?? [:])
                        }
                    case "thinking", "redacted_thinking":
                        if s.newest == nil { s.newest = .thinking }
                    case "text":
                        let text = (block["text"] as? String ?? "")
                            .replacingOccurrences(of: "**", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if s.newest == nil {
                            s.newest = .text
                            s.ended = (m["stop_reason"] as? String) == "end_turn"
                        }
                        if s.lastText == nil, !text.isEmpty { s.lastText = clip(text, 400) }
                    default: break
                    }
                }
            case "user":
                guard let m = o["message"] as? J else { continue }
                if s.humanPrompt == nil, (o["origin"] as? J)?["kind"] as? String == "human",
                    o["isMeta"] as? Bool != true
                {
                    let text =
                        m["content"] as? String
                        ?? (m["content"] as? [J])?.compactMap { $0["text"] as? String }
                            .joined(separator: " ")
                    if let text, !text.isEmpty { s.humanPrompt = clip(oneLine(text), 300) }
                }
                let isToolResult =
                    (m["content"] as? [J])?.contains { $0["type"] as? String == "tool_result" } ?? false
                if !isToolResult { toolSearchClosed = true }
                if s.newest == nil { s.newest = isToolResult ? .toolResult : .prompt }
            default: break
            }

            // A tool named after the newest event was a text/prompt is stale; stop looking.
            let toolSettled =
                s.tool != nil || toolSearchClosed || s.newest == .text || s.newest == .prompt
                || s.newest == .thinking
            if s.newest != nil, s.lastText != nil, s.contextTokens != nil, toolSettled,
                !wantMeta || (s.title != nil && s.humanPrompt != nil)
            {
                break
            }
        }
        // Subagents hand their result back through this tool as their final step.
        if s.tool == "SubagentHandback", s.newest == .toolUse || s.newest == .toolResult {
            s.ended = true
        }
        if s.newest == .text || s.newest == .prompt || s.newest == .thinking {
            s.tool = nil
            s.toolDetail = nil
        }
        return s
    }

    private static func toolDetail(_ input: J) -> String? {
        for key in ["description", "command", "file_path", "pattern", "query", "url", "skill", "prompt"] {
            if let v = input[key] as? String, !v.isEmpty { return clip(oneLine(v), 140) }
        }
        return nil
    }

    private static func oneLine(_ s: String) -> String {
        s.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func clip(_ s: String, _ n: Int) -> String {
        s.count > n ? String(s.prefix(n)) + "…" : s
    }
}
