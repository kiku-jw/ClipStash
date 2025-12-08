# ClipStash

[![Build](https://github.com/kiku-jw/ClipStash/actions/workflows/ci.yml/badge.svg)](https://github.com/kiku-jw/ClipStash/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-brightgreen)](https://www.apple.com/macos/)

Lightweight, privacy-first clipboard history manager for macOS menu bar.

## Features

- **Always Running**: Menu bar app, captures clipboard in background
- **Privacy First**: Fully offline, no network access, no telemetry
- **Fast Search**: SQLite FTS5 full-text search
- **Low Resource**: < 60 MB RAM, < 0.5% CPU idle
- **Export**: NotebookLM-friendly Markdown export with auto-split

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ for building

## Installation

### From Source

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

## Usage

### Basic

- Click menu bar icon to open history
- `↑/↓` — Navigate items
- `Enter` — Copy to clipboard
- `⌘F` — Focus search
- `⌘⌫` — Delete item
- `⌘P` — Pin/unpin item

### Export to NotebookLM

1. Click "Export..." in popover
2. Select items: Last 50/100/200/500 or Pinned only
3. Choose format: Markdown (recommended)
4. Click Export
5. Use "Open NotebookLM" to upload files

Large exports auto-split into ~180KB files for NotebookLM compatibility.

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
