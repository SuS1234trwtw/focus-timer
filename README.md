# Focus — Pomodoro timer for iOS 26

A minimalist Pomodoro timer built around one giant, carved numeral. Native SwiftUI app (iOS 26+) with an offline-first SwiftData store that syncs to Supabase.

- A vertical reel of chiseled 3D minute numerals: **scroll** to pick the length, **tap** to start/pause, **hold** to reset
- The numeral lights up with a burst when a block starts; the reel rolls down as minutes pass
- Focus is dark, break inverts to light; at zero a gentle chime plays and a `+00:00:00` overtime count runs until you tap
- Settings (sliders icon): timer font (Block, Hairline, Mono, Round, Serif), focus/break lengths, chime on/off
- Tasks (checklist icon): add, check off, swipe to delete, tap to make one active; it shows under the timer
- Tasks and completed sessions sync to Supabase (anonymous auth + row-level security); works fully offline

## Layout

```
project.yml                 XcodeGen spec (the .xcodeproj is generated, not committed)
Config/                     Base.xcconfig + your gitignored Secrets.xcconfig
FocusTimer/                 app source
  Timer/                    PomodoroEngine (state machine), NumeralReel (3D numerals + burst), chime
  Tasks/                    SwiftData models, task actions, TasksSheet
  Sync/                     SupabaseService, SyncCoordinator (push/pull, last-write-wins)
  Views/                    RootView, SettingsSheet
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

To test full cycles quickly, add `-fastTimer` under *Scheme → Run → Arguments* (each "minute" lasts one second).

## Getting it onto an iPhone

Installing on a real device needs code signing: either Xcode on a Mac with your Apple ID (free accounts work for your own phone, re-sign every 7 days), or an Apple Developer Program membership for TestFlight via Xcode Cloud or a signed CI job.
