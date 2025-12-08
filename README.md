<p align="center">
  <img src="assets/icon.png" alt="ClipStash" width="128" height="128">
</p>

<h1 align="center">ClipStash</h1>

<p align="center">
  <strong>🗒️ Lightweight, privacy-first clipboard history manager for macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/kiku-jw/ClipStash/actions"><img src="https://github.com/kiku-jw/ClipStash/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14%2B-brightgreen" alt="macOS 14+"></a>
</p>

<p align="center">
  <a href="https://kiku-jw.github.io/ClipStash">Website</a> •
  <a href="https://github.com/kiku-jw/ClipStash/wiki">Documentation</a> •
  <a href="https://github.com/kiku-jw/ClipStash/releases/latest/download/ClipStash.app.zip">Download</a>
</p>

---

## Why ClipStash?

ClipStash is an **open-source clipboard manager** for macOS that prioritizes **privacy** and **performance**. Unlike alternatives that require internet access or heavy frameworks, ClipStash runs completely offline with zero telemetry.

### ✨ Key Features

| Feature | Description |
|---------|-------------|
| 🔒 **Zero Network Access** | Sandbox enforced — literally cannot connect to internet |
| ⚡ **Lightning Search** | SQLite FTS5 full-text search across thousands of items |
| 📤 **NotebookLM Export** | Auto-split Markdown files for AI notebooks (unique!) |
| 🔐 **Password-Aware** | Auto-skips 1Password, Bitwarden, and other managers |
| 🪶 **Ultralight** | <60MB RAM, <0.5% CPU idle, native SwiftUI |
| 📌 **Pin & Organize** | Pin frequently used clips, filter by source app |
| 🖼️ **Image Support** | Capture and preview images in clipboard history |

---

## Comparison with Alternatives

| Feature | ClipStash | Maccy | CopyQ | PasteBar | Ditto |
|---------|:---------:|:-----:|:-----:|:--------:|:-----:|
| **Platform** | macOS | macOS | Cross | Mac/Win | Windows |
| **Open Source** | ✅ MIT | ✅ MIT | ✅ GPL | ✅ Apache | ✅ GPL |
| **Zero Network** | ✅ Sandboxed | ✅ | ❌ | ✅ | ✅ |
| **FTS5 Search** | ✅ | ✅ | ❌ | ❌ | Regex |
| **NotebookLM Export** | ✅ **Unique** | ❌ | ❌ | ❌ | ❌ |
| **Password Detection** | ✅ Both flags | ✅ | Script | ❌ | ❌ |
| **App Filter Export** | ✅ | ❌ | ❌ | Partial | ❌ |
| **Native UI** | ✅ SwiftUI | ✅ AppKit | Qt | Tauri | Win32 |
| **RAM Usage** | ~50MB | ~40MB | ~100MB | ~150MB | ~30MB |
| **Price** | Free | Free | Free | Free | Free |

> **Bottom line:** ClipStash is the only clipboard manager with NotebookLM-optimized export and verifiable zero-network privacy (sandbox enforced, open source).

---

## Installation

### Download Release

[⬇️ **Download ClipStash.app.zip**](https://github.com/kiku-jw/ClipStash/releases/latest/download/ClipStash.app.zip)

1. Download and unzip
2. Run in Terminal: `xattr -cr ~/Downloads/ClipStash.app`
3. Move `ClipStash.app` to `/Applications` and launch

> **Why xattr?** macOS blocks apps not signed with Apple Developer ID ($99/year). This command removes the quarantine flag. ClipStash is open-source — [verify the code](https://github.com/kiku-jw/ClipStash).

### Build from Source

```bash
git clone https://github.com/kiku-jw/ClipStash.git
cd ClipStash
open ClipStash.xcodeproj
# Build with ⌘B, Run with ⌘R
```

### Launch at Login

1. Move `ClipStash.app` to `/Applications`
2. Open Settings → Enable "Launch at Login"

> Note: Launch at login requires the app to be in `/Applications` (macOS restriction).

---

## Usage

### Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| Open history | Click menu bar icon |
| Navigate | `↑` / `↓` |
| Copy to clipboard | `Enter` |
| Focus search | `⌘F` |
| Delete item | `⌘⌫` |
| Pin/unpin | `⌘P` |
| View full content | Double-click |

### Export to NotebookLM

1. Click **Export...** in popover
2. Select scope: Last 50/100/200/500, Today, Pinned, or by App
3. Choose format: Markdown (recommended)
4. Click **Export Now**

Large exports auto-split into **~180KB files** for NotebookLM's source limit.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| History Limit | 500 | Max items to keep (100-2000) |
| Text Max Size | 200 KB | Skip text larger than this |
| Image Max Size | 5 MB | Skip images larger than this |
| Save Images | Off | Also capture images |
| Deduplication | On | Skip duplicate content |
| Byte Preserve | Off | Keep exact whitespace |

### Ignore List

Add app bundle IDs to exclude from capture (e.g., `com.1password.1password`).

## Privacy

- **No Network**: App never makes network requests (sandbox enforced)
- **No Telemetry**: Zero analytics or tracking
- **Local Storage**: All data in `~/Library/Application Support/ClipStash`
- **Sensitive Content**: Automatically skips concealed/transient clipboard items
- **Optional Encryption**: Pin items and encrypt with AES-GCM

### Sensitive Content Detection

ClipStash respects macOS clipboard indicators:
- `org.nspasteboard.ConcealedType` — password managers
- `org.nspasteboard.TransientType` — temporary data

## Architecture

```
ClipStash/
├── App/           # Entry point, AppDelegate
├── Core/          # Business logic
│   ├── ClipboardMonitor.swift
│   ├── StorageManager.swift
│   └── ExportService.swift
├── UI/            # SwiftUI views
└── Utils/         # Helpers
```

### Why Polling?

macOS doesn't provide clipboard change notifications. We poll `NSPasteboard.changeCount` every 300ms with debounce — same approach used by established clipboard managers. This uses negligible CPU.

## FAQ

**Q: Why not use NSPasteboard notifications?**
A: macOS doesn't provide them. Polling is the only reliable method.

**Q: How do I exclude an app?**
A: Settings → Ignore List → Add bundle ID (e.g., `com.apple.keychainaccess`).

**Q: Where is data stored?**
A: `~/Library/Application Support/ClipStash/clipstash.db`

**Q: How to fully uninstall?**
A: Delete app + `rm -rf ~/Library/Application\ Support/ClipStash`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
