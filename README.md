<p align="center">
  <a href="https://sus1234trwtw.github.io/"><img src="docs/banner.png" alt="Focus: a minimal Pomodoro timer and task list for iPhone, with a terminal-inspired look" width="100%"></a>
</p>

<h3 align="center">
  <a href="https://sus1234trwtw.github.io/">sus1234trwtw.github.io</a>
</h3>

<p align="center">
  <a href="https://sus1234trwtw.github.io/"><img alt="Website" src="https://img.shields.io/badge/website-sus1234trwtw.github.io-f5f5f2?style=flat-square&labelColor=050505"></a>
  <a href="https://github.com/SuS1234trwtw/focus-timer/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/SuS1234trwtw/focus-timer?style=flat-square&label=download&color=f5f5f2&labelColor=050505"></a>
  <a href="https://sus1234trwtw.github.io/install.html"><img alt="Install guide" src="https://img.shields.io/badge/install-step--by--step-f5f5f2?style=flat-square&labelColor=050505"></a>
  <img alt="iOS 26+" src="https://img.shields.io/badge/iOS-26%2B-f5f5f2?style=flat-square&labelColor=050505">
  <a href="LICENSE"><img alt="All rights reserved" src="https://img.shields.io/badge/license-all%20rights%20reserved-f5f5f2?style=flat-square&labelColor=050505"></a>
</p>

<p align="center">
  <a href="https://sus1234trwtw.github.io/"><b>Website</b></a> &nbsp;·&nbsp;
  <a href="https://sus1234trwtw.github.io/install.html"><b>Install guide</b></a> &nbsp;·&nbsp;
  <a href="https://github.com/SuS1234trwtw/focus-timer/releases/latest"><b>Download IPA</b></a> &nbsp;·&nbsp;
  <a href="https://sus1234trwtw.github.io/privacy.html">Privacy</a> &nbsp;·&nbsp;
  <a href="https://sus1234trwtw.github.io/terms.html">Terms</a>
</p>

---

# Focus — Pomodoro timer for iOS 26

A minimal Pomodoro timer and task list for iPhone with a terminal look. Native SwiftUI app (iOS 26+) with an offline-first SwiftData store that syncs to Supabase.

- Focus / break timer with custom lengths, sounds and Core Haptics
- Five terminal styles (Mono, the default, matches the website; plus Cozy, PowerShell, CMD, Ubuntu), each with 16 mono fonts
- Dynamic Island and lock-screen Live Activity with pause and switch-mode buttons, plus Home Screen widgets
- Task list: add, check off, delete, and tap a task to make it the one you're focusing on
- Optional Spotify now-playing controls and Google Calendar logging of finished focus blocks
- Tasks and sessions sync to Supabase (anonymous auth + row-level security); works fully offline
- In-app update notices, plus a SideStore source for one-tap updates

## Layout

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
Config/                     Base.xcconfig + your gitignored Secrets.xcconfig
FocusTimer/                 app source
  Timer/                    PomodoroEngine (state machine), TimerView, chime + notifications
  Tasks/                    SwiftData models, task actions, TaskListView
  Sync/                     SupabaseService, SyncCoordinator (push/pull, last-write-wins)
  Views/                    RootView, header, terminal overlay
  Resources/                chime.wav, asset catalog, Fonts/ (fetched)
FocusTimerTests/            Swift Testing: engine + sync merge
supabase/migrations/        database schema + RLS policies
scripts/                    fetch-fonts.sh, generate_assets.py (chime + icon)
.github/workflows/ios.yml   CI: build + test on a macOS runner
```

## Backend setup (Supabase)

1. Apply `supabase/migrations/0001_init.sql` to your project (SQL editor or `supabase db push`).
2. In the dashboard, go to **Authentication → Sign In / Providers** and turn on **Allow anonymous sign-ins**.
3. Note the project host (`<ref>.supabase.co`) and the anon/publishable key.

Without these values the app runs in local-only mode (status line shows `○ local`).

## Build in CI (no Mac needed)

1. Push this folder to a GitHub repo.
2. Add repository secrets `SUPABASE_HOST` (for example `abcd1234.supabase.co`, no `https://`) and `SUPABASE_ANON_KEY`.
3. The **iOS** workflow generates the project, builds it for the simulator, and runs the tests. Logs and the `.xcresult` bundle are uploaded as artifacts.

## Build on a Mac (Xcode 26)

```bash
brew install xcodegen
./scripts/fetch-fonts.sh
cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig   # then fill it in
xcodegen generate
open FocusTimer.xcodeproj
```

To test full cycles quickly, add `-fastTimer` under *Scheme → Run → Arguments* (10s focus / 5s break).

## Getting it onto an iPhone

Installing on a real device needs code signing: either Xcode on a Mac with your Apple ID (free accounts work for your own phone, re-sign every 7 days), or an Apple Developer Program membership for TestFlight via Xcode Cloud or a signed CI job.

## Install

Download the latest IPA from [Releases](https://github.com/SuS1234trwtw/focus-timer/releases/latest) and follow the [step-by-step install guide](https://sus1234trwtw.github.io/install.html) (iloader or SideStore, Windows or Mac). SideStore source for one-tap updates:

```
https://github.com/SuS1234trwtw/focus-timer/releases/latest/download/source.json
```

## License

Copyright © 2026 An Le. All rights reserved: the code is public to read, not to copy or reuse ([LICENSE](LICENSE)). Bundled fonts are downloaded at build time and stay under their own licenses (SIL Open Font License, Ubuntu Font Licence, Apache 2.0).

Website, privacy policy and terms: https://sus1234trwtw.github.io/

```bash
creator note:
hoi chieu....... hoio chieuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu t-t--t-t-t-t-t-t-t-tt-t-t-t-t-t-t-troi m-m-m--mm-m-m-m-m-m-mua
