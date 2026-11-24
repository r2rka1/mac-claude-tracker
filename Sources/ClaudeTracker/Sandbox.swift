import AppKit
import Darwin

/// The Mac App Store build runs in the App Sandbox. Two things change there:
/// `~/.claude` is only readable after the user picks it in an open panel, and
/// per-process CPU and memory are not available at all.
enum Sandbox {
    static let active = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// The user's real home folder (NSHomeDirectory() is the container when sandboxed).
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return URL(fileURLWithPath: NSHomeDirectory())
    }
}

/// Where Claude Code keeps its data, and the permission to read it.
final class ClaudeFolder {
    static let shared = ClaudeFolder()
    private static let key = "claudeFolderBookmark"
    private let lock = NSLock()
    private var granted: URL?

    private init() {
        guard Sandbox.active, let data = UserDefaults.standard.data(forKey: Self.key) else { return }
        var stale = false
        guard
            let url = try? URL(
                resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                bookmarkDataIsStale: &stale),
            url.startAccessingSecurityScopedResource()
        else { return }
        granted = Self.claudeRoot(in: url)
        if stale { save(url) }
    }

    /// The `.claude` folder, or nil when the sandboxed app has not been given access yet.
    var root: URL? {
        guard Sandbox.active else { return Sandbox.realHome.appendingPathComponent(".claude") }
        lock.lock()
        defer { lock.unlock() }
        return granted
    }

    /// Asks the user for the folder. Returns false if they cancel or pick something else.
    @MainActor func requestAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Choose your .claude folder so Claude Tracker can read session activity. "
            + "It is only ever read, never changed."
        panel.prompt = "Allow"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Sandbox.realHome.appendingPathComponent(".claude")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let root = Self.claudeRoot(in: url)
        else { return false }
        save(url)
        lock.lock()
        granted = root
        lock.unlock()
        return true
    }

    /// Accepts the `.claude` folder itself or a folder containing it (such as the home folder).
    private static func claudeRoot(in url: URL) -> URL? {
        let fm = FileManager.default
        for candidate in [url, url.appendingPathComponent(".claude")]
        where fm.fileExists(atPath: candidate.appendingPathComponent("projects").path) {
            return candidate
        }
        return nil
    }

    private func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
