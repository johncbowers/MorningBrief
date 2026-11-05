# Morning Brief

A native SwiftUI macOS reader for a Markdown briefing produced by an existing assistant. macOS 13 or later; the supplied app is built for Apple Silicon.

## Run

Open `dist/Morning Brief.app`. For permanent use, quit it, copy it to Applications, then open that copy before enabling **Launch at login** in Preferences (⌘,). The app remains running in the menu bar after its window closes. Quit stops background checks.

This local build is ad-hoc signed, not Developer ID signed or notarized. macOS may require approval in Privacy & Security when the app is transferred to another Mac. A Developer ID certificate is needed for normal public distribution.

## Briefing setup

Choose the local folder where your assistant writes its briefings in Preferences. For daily files named `2026-11-05.md`, use:

- Filename pattern: `{date}.md`
- Date format: `yyyy-MM-dd`
- Require modified today: off (the filename determines the date)
- Automatic opening: 08:00 through 14:59 local time

This excludes files such as `2026-11-05-review.md`. Briefings can arrive before 8 a.m.; automatic opening waits until the configured start time. Preferences are stored on the current Mac, not embedded in the distributable. A new installation starts with folder selection.

Preferences also support `*` wildcards. To use an undated file, enter its exact name, such as `summary.md`, and enable **Require file to be modified today**. Only immediate children of the folder are scanned; subfolders are excluded. If several files match, newest modification time wins, with filename as a deterministic tie breaker. Files must be nonempty UTF-8 `.md` or `.markdown`, at most 5 MB, and have been unchanged for at least two seconds. An atomic file rename by the producer is recommended.

## Morning behavior

While running, the app checks every 30 seconds and immediately on wake, session activation, and screen unlock. If today’s file is ready, automatic opening is enabled, the session is active/unlocked, and the current hour falls within the configured window, it brings its window forward once. If the file arrives late, a later check opens it. There is no fallback to yesterday’s file. No file means a waiting screen; an inaccessible folder produces an error.

The opened-day record persists across restarts. A loaded briefing in the visible reader counts as opened, including manual opening. Updates still reload without repeated activation. The record uses the Mac’s current local calendar date and time zone. An app launched after the cutoff stays in the background; open it from its Dock or menu-bar icon to read manually. If the computer stays asleep or locked until after cutoff, it will not automatically open that day. Increase the cutoff if desired.

Login launch uses Apple’s `SMAppService.mainApp`. Enable it after moving the app into its permanent location, and approve it in System Settings → General → Login Items if macOS requests approval. Login launch is optional and is initially off. This is a running app, not a separate launch agent: it cannot observe wakes or unlocks while quit.

## Rendering and privacy

SwiftUI provides the native window and preferences; WKWebView displays styled HTML rendered offline by bundled markdown-it 14.1.0. Includes headings, lists, blockquotes, tables, fenced code, emphasis, and links, with light/dark appearance. Raw HTML is escaped. Page JavaScript, remote images, and external resource loading are disabled. HTTP, HTTPS, and mail links open only when clicked, through macOS. Relative file links/images are not supported. No briefing data is uploaded or bundled into releases. Instructions appearing inside a briefing are displayed as content, never executed.

## Build and test

Install Apple Command Line Tools (`xcode-select --install`) if necessary. Full Xcode is not required. From this directory:

```sh
./build.sh
./test.sh
open "dist/Morning Brief.app"
```

`build.sh` compiles the Swift sources, copies the offline resources and Info.plist, and ad-hoc signs the app. It targets Apple Silicon / macOS 13. To build for Intel with an appropriate SDK, change `arm64-apple-macosx13.0` to `x86_64-apple-macosx13.0`; universal distribution requires building both architectures and joining them with `lipo` before signing. No network access is needed to rebuild.

Sources: `Sources/App.swift` (UI, reader, lifecycle, folder checks), `Sources/BriefingCore.swift` (date matching and opening policy). The bundled renderer’s MIT license is in `Resources/markdown-it.LICENSE`.

## Verification

Automated checks cover dated names, stale files, extension exclusion, missing files, lock gating, start/cutoff boundaries, late arrival and daily deduplication. The local app was built and its preferences, sample headings/lists/tables/links and reader layout were checked in the running UI. The actual `2026-11-05.md` briefing was also loaded and verified in the running app. A complete overnight login/wake cycle and login-item approval still need testing on the target Mac; simulated policy checks do not substitute for those OS lifecycle checks.

Manual lifecycle check: enable login launch from the permanent app location; close the reader; on a subsequent morning unlock after start time. Confirm one opening. Close and unlock again to confirm suppression. To check a late arrival, use a disposable folder with today’s matching file absent, then add a nonempty Markdown file after start time; expect opening within about 30 seconds after the write settles. Never move or rename your production briefing just to test.
