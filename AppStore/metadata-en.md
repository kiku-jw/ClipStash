# ClipStash App Store metadata — English (U.S.)

> Document class: release input. This file is the canonical copy source for
> the ClipStash macOS listing. It is prepared from the current checkout and is
> not an App Store Connect submission. Reconcile it when the listing changes.

## App identity

- **App Store name:** `ClipStash Pro` (13/30 characters)
- **App Store:** https://apps.apple.com/app/clipstash-pro/id6756281955
- **Platform:** macOS 14.0 or later
- **Primary category in the project:** Productivity
- **Bundle ID:** `dev.kikuai.ClipStash`
- **Source marketing version:** `1.0.2`
- **Source build number:** `4`
- **Primary language supported by this checkout:** English (U.S.)

App Store Connect was checked on 2026-09-30: public version 1.0.1 uses build 3.
The promotional text below was saved to the current version. A 1.0.2 draft
contains the remaining fields below, but has no selected build and has not
been submitted. This checkout prepares source version 1.0.2, build 4.
Re-open App Store Connect before release; the dated check is not live status.

## Product page fields

### Subtitle

`Clipboard History for Mac`

25/30 characters.

### Promotional text

`Find copied text and images, pin what matters, filter by app, and export selected history as Markdown or plain text.`

Within the 170-character limit.

### Keywords

`pasteboard,copy,paste,search,pin,images,markdown,plaintext,menubar,local,productivity`

Within the 100-byte limit. These terms do not repeat the name or subtitle and do not use
competitor or Apple product names.

### Description

ClipStash Pro keeps a searchable history of text and images you copy on your Mac. Open it from the menu bar, find an earlier clip, and copy it back when you need it.

Use ClipStash Pro to:

• Capture text and optionally copied images while the app is running.
• Search your history and browse by content type or source app.
• Pin items you reuse and keep pinned items when clearing other history.
• Remove individual clips or clear the history.
• Skip duplicate entries and ignore clipboard items marked as concealed or transient.
• Add apps to an ignore list.
• Export recent items, today’s items, pinned items, or clips from selected apps.
• Choose Markdown or plain text, optionally include image references, and split large exports into smaller files.

Your history is processed locally and stored on your Mac. No account or cloud sync is required. Exported files stay in your chosen destination; optional actions can open Finder or an external web destination.

ClipStash Pro is a macOS menu bar utility for macOS 14 or later.

Within the 4,000-character limit.

### Release notes candidate — not submitted

Use this note only for a new build that includes the search and export fixes below
and has been reviewed against the live App Store Connect record:

Search now handles quotation marks in queries. Choose where to save exported history with the native folder picker.

## Source-backed scope

The copy above is intentionally narrower than older public materials:

- Clipboard capture, size limits, deduplication, concealed/transient flags,
  and ignored apps: `ClipStash/Core/ClipboardMonitor.swift`.
- Local SQLite storage, search, pinning, clearing, and source-app filtering:
  `ClipStash/Core/StorageManager.swift` and `ClipStash/UI/PopoverView.swift`.
- Export scopes, Markdown/plain-text formats, optional image references,
  user-selected output (Downloads starts the picker), and the approximately
  400,000-word file split target:
  `ClipStash/Core/ExportService.swift` and `ClipStash/UI/SettingsView.swift`.
- macOS deployment target, bundle ID, marketing version, and build number:
  `ClipStash.xcodeproj/project.pbxproj`.

Do not restore claims that this checkout cannot prove, including zero network
access, encryption of pinned items in the product workflow, fixed memory/CPU/
latency figures, invisible operation, or unique market position. The app can
open Finder and external web destinations when a user chooses those actions.

The old live build 3 copy is therefore not reused: its claims about
being the only clipboard manager, AI notebook export, zero network access,
enforced sandboxing, instant or millisecond search, fixed memory size, JSON,
180 KB, and never using the internet are outside this source-backed candidate.

## Release handoff

### Current artifacts

- The repository source declares candidate version `1.0.2` / build `4`.
- The latest GitHub release currently visible for `kiku-jw/ClipStash` is
  `v0.1.0`, with `ClipStash.app.zip` attached. This is a historical unsigned
  direct-download archive, not evidence of the current App Store build.
- No `.xcarchive` or current App Store archive is checked into this checkout.

### Safe preflight

Before any archive or upload, re-check the exact build settings without
building:

```sh
xcodebuild -project ClipStash.xcodeproj -scheme ClipStash \
  -configuration Release -showBuildSettings \
  | rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|PRODUCT_BUNDLE_IDENTIFIER|DEVELOPMENT_TEAM|CODE_SIGN_ENTITLEMENTS'
```

The existing GitHub release workflow builds an unsigned direct-download zip
when a GitHub release is published. It is not an App Store upload command. An
App Store archive/export still requires the owner's signing team, certificates,
profiles, and reviewed App Store Connect metadata; none of those are supplied
or changed here. Do not publish or submit a release from this file.

### Sandbox readiness

The candidate now declares App Sandbox and
`com.apple.security.files.user-selected.read-write` in
`ClipStash/ClipStash.entitlements`. Both export views open a native directory
picker with Downloads as the starting location, hold the selected parent URL
only for the export operation, and write each export into a fresh
`ClipStash_Export_*` child folder. `ExportService` requires that caller-selected
destination and no longer chooses Downloads implicitly. There is no network
entitlement. A signed runtime check is still required before describing
sandbox behavior as enforced; this checkout is not an App Store submission
artifact.

The installed baseline was inspected without launching it: `/Applications/ClipStash.app`
is version 1.0.1/build 3 with bundle ID
`dev.kikuai.ClipStash`, and its signed entitlements already contain App
Sandbox plus user-selected read/write access. Its history database is under
`~/Library/Containers/dev.kikuai.ClipStash/Data/Library/Application Support/ClipStash`,
which matches the source's user-domain Application Support lookup
when the same bundle is sandboxed. The uncontainerized
`~/Library/Application Support/ClipStash` path is a separate legacy/direct-build
store and is not copied or modified by this candidate. The new source migration
only adds the existing schema index in place. App Store Connect must still
verify the transferred signing team and container continuity before upload;
the candidate was never launched against the user's real history.
