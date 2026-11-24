# Publishing Claude Tracker on the Mac App Store

Everything that can be prepared in the repository is here. The steps marked **you** need your Apple Developer account and cannot be scripted from this repo.

## Status

| Item | State |
| --- | --- |
| Sandboxed universal build (`scripts/build-appstore.sh`) | ready; `--local` builds and runs |
| Entitlements (`Resources/AppStore.entitlements`) | ready |
| App icon with 1024 px size (`Resources/AppIcon.icns`) | ready |
| Screenshots, 2880 × 1800 (`appstore/screenshots/`) | ready |
| Marketing / support site | https://r2rka1.github.io/mac-claude-tracker/ |
| Privacy policy | https://r2rka1.github.io/mac-claude-tracker/privacy.html |
| Listing text | below |
| Apple Developer Program membership, certificates, app record | **you** |

## Steps

1. **You:** join the [Apple Developer Program](https://developer.apple.com/programs/) (paid). The "Apple Development" certificate currently in the keychain cannot sign App Store builds.
2. **You:** at developer.apple.com → Certificates, IDs & Profiles:
   - register the App ID `io.github.r2rka1.ClaudeTracker` (or your own; pass it as `BUNDLE_ID`), no extra capabilities;
   - create an **Apple Distribution** and a **Mac Installer Distribution** certificate and install both in the keychain;
   - create a **Mac App Store Connect** provisioning profile for the App ID and download it.
3. **You:** in [App Store Connect](https://appstoreconnect.apple.com) create a new macOS app with that bundle ID. **Name risk:** "Claude" is Anthropic's trademark, and App Review can reject names that lead with another company's mark (guideline 5.2.1). If that happens, a descriptive form such as "Session Tracker for Claude Code" usually passes; the bundle display name is one line in `Resources/Info.plist`.
4. Build and sign:
   ```sh
   PROFILE=~/Downloads/ClaudeTracker.provisionprofile VERSION=1.0 BUILD=1 ./scripts/build-appstore.sh
   ```
   This writes `build/appstore/ClaudeTracker.pkg`.
5. **You:** upload the package with the Transporter app (or `xcrun altool`, the script prints the command).
6. **You:** fill in the listing from the text below, upload `appstore/screenshots/*.png`, answer the privacy questionnaire with **Data Not Collected**, set the price to Free, and submit for review.

Try the sandboxed build on this Mac first: `./scripts/build-appstore.sh --local && open build/appstore/ClaudeTracker.app`.

## Listing

- **Name:** Claude Tracker
- **Subtitle:** Claude Code sessions at a glance
- **Category:** Developer Tools
- **Price:** Free
- **Age rating:** 4+
- **Copyright:** 2026 Arthur Artsabliuk
- **Support URL:** https://github.com/r2rka1/mac-claude-tracker/issues
- **Marketing URL:** https://r2rka1.github.io/mac-claude-tracker/
- **Privacy Policy URL:** https://r2rka1.github.io/mac-claude-tracker/privacy.html
- **Keywords:** claude code,ai agent,menu bar,system monitor,cpu,memory,disk,developer,sessions,subagents

**Promotional text**

See what every Claude Code session and subagent on your Mac is doing, next to live CPU, memory and disk, from the menu bar.

**Description**

Claude Tracker is a compact menu bar monitor for people who run several Claude Code sessions at once.

The menu bar shows CPU, memory, and how many sessions are busy. Click it for the panel:

• Sessions: every live Claude Code session with its project, title, busy or idle state, context size and time since last activity.
• Current step: busy sessions show what the agent is doing (running a tool, thinking, writing), the last prompt and the latest reply.
• Subagents: running subagents are listed under their session with their own current step.
• System: CPU with a sparkline and load average, memory and swap, free disk space.

Private by design: the app only reads local files on your Mac, read-only. It makes no network requests and collects nothing.

On first launch the app asks you to choose the .claude folder in your home folder, so it can read session activity.

Claude Tracker is an independent open-source project and is not affiliated with Anthropic. Requires Claude Code to be installed for the session view.

**Screenshots**

1. `1.png`: sessions and subagents (dark)
2. `2.png`: system stats and menu bar item (light)

Regenerate them with `ClaudeTracker --render-store appstore/screenshots` (example data only).

## App privacy

Data Not Collected. The app makes no network requests. It reads system statistics and, after the user picks the folder, Claude Code's local session files, only to display them.

## Notes for App Review

- The app lives in the menu bar (no Dock icon). Click the `C…% M…%` item at the right of the menu bar.
- To show Claude Code sessions it needs read access to the `.claude` folder in the user's home folder. It asks through a standard open panel ("Allow access to .claude…") and keeps a security-scoped bookmark. Nothing is written there.
- Without Claude Code installed the session list is empty; the system statistics work on any Mac.
- No account, no network access, no in-app purchases.

## What differs from the direct build

The App Sandbox does not let an app read other processes' CPU or memory (`ps` and `libproc` are blocked). The App Store edition therefore shows the process count but not the top-process lists or per-session CPU. The build from `scripts/build-app.sh` keeps them.
