# Contributing to ClipStash

Thank you for your interest in contributing!

## Development Setup

1. Clone the repository
2. Open `ClipStash.xcodeproj` in Xcode 15+
3. Build with ⌘B

## Isolated history check

On macOS 14+ with the Swift toolchain installed, run:

```sh
bash scripts/test-isolated-history.sh
```

This compiles the actual storage, export, item and ViewModel sources in a temporary,
dependency-free Swift package. It checks generated history → search → pin → copy
to a uniquely named pasteboard → Markdown export → close and reopen. Both storage
and pasteboard must be provided together; partial test injection is not supported.
It uses a temporary database and named pasteboard, without launching the app,
clipboard monitor, a control server, or accessing the general pasteboard. The
temporary package and fixture are removed after the run. Keep the command output
when recording results. This does not verify live capture, exclusion behavior,
native windows, Store signing or upgrading a user's existing database.

## Code Style

- Swift 5.9+ with modern concurrency (async/await, actors)
- SwiftUI for UI, AppKit only for system integration
- Use `@MainActor` for UI state
- Keep files focused and small

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make changes with clear commit messages
4. Add tests for new functionality
5. Ensure all tests pass: `xcodebuild test`
6. Submit a pull request

## Reporting Issues

- Use GitHub Issues
- Include macOS version
- Provide steps to reproduce
- Attach relevant logs from Console.app

## Code of Conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
