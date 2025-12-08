# Contributing to ClipStash

Thank you for your interest in contributing!

## Development Setup

1. Clone the repository
2. Open `ClipStash.xcodeproj` in Xcode 15+
3. Build with ⌘B

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
