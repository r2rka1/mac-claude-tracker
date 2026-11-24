import SwiftUI

/// App Store screenshots (2880×1800), composed offscreen from made-up data.
enum StoreShots {
    static let size = CGSize(width: 1440, height: 900)

    @MainActor static func render(into dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let m = Main.renderMonitor(demo: true, store: true)
        let shots: [(String, String, Bool)] = [
            ("Every Claude Code\nsession at a glance",
             "See which sessions are busy, the step each agent is on, and what its subagents are doing.", true),
            ("Your Mac's vitals,\none click away",
             "CPU, memory and disk live in the menu bar, next to a count of busy sessions.", false),
        ]
        for (i, shot) in shots.enumerated() {
            let view = Shot(title: shot.0, subtitle: shot.1, menuTitle: m.menuTitle) {
                DashboardView(inWindow: false).environmentObject(m).tint(Mascot.tint)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Main.png(of: view, size: size, dark: shot.2, to: "\(dir)/\(i + 1).png")
        }
    }
}

/// Headline on the left, the panel hanging from a menu bar on the right.
private struct Shot<Panel: View>: View {
    let title: String
    let subtitle: String
    let menuTitle: String
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(nsColor: Mascot.rgb(0x4C2FB0)), Color(nsColor: Mascot.rgb(0x150F33))],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                Spacer()
                Text(menuTitle).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.22)))
                    .padding(.trailing, 250)
            }
            .foregroundStyle(.white)
            .frame(height: 30)
            .background(Color.black.opacity(0.28))

            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 22) {
                    Image(nsImage: Mascot.image(size: 128)).interpolation(.none)
                    Text(title).font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle).font(.system(size: 24, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(nsColor: Mascot.rgb(0xDDD6FE)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 600, alignment: .leading)
                .padding(.top, 170)

                panel()
                    .fixedSize()
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                    .scaleEffect(1.3, anchor: .top)
                    .padding(.top, 40)
            }
            .padding(.horizontal, 90)
        }
        .frame(width: StoreShots.size.width, height: StoreShots.size.height)
    }
}
