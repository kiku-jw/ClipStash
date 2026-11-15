import AppKit
#if CLIPSTASH_STANDALONE
class ClipboardMonitorTestCase {}
#else
import XCTest
@testable import ClipStash
typealias ClipboardMonitorTestCase = XCTestCase
#endif

@MainActor
final class ClipboardMonitorTests: ClipboardMonitorTestCase {
    private final class Pasteboard: ClipboardPasteboard {
        var changeCount = 0
        var types: [NSPasteboard.PasteboardType]? = [.string]
        var text: String?
        var image: Data?
        var onRead: (() -> Void)?

        func copy(_ text: String) {
            changeCount += 1
            self.text = text
            types = [.string]
        }

        func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
            guard dataType == .string else { return nil }
            onRead?()
            return text
        }

        func data(forType dataType: NSPasteboard.PasteboardType) -> Data? {
            dataType == .png ? image : nil
        }
    }

    private struct Settings: ClipboardCaptureSettings {
        var bytePreserveMode = false
        var textMaxBytes = 500_000
        var imageMaxBytes = 10_000_000
        // Disable content dedup so it cannot hide duplicate polling inserts.
        var dedupEnabled = false
        var historyLimit = 500
        var saveImages = true
        var ignoreConcealed = true
        var ignoreTransient = true
        func isIgnored(bundleId: String?) -> Bool { bundleId == "test.ignored" }
    }

    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_000)
    }

    private enum Failure: Error {
        case expectation(String)
    }

    private func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure.expectation(message) }
    }

    private func withFixture(_ body: (StorageManager, URL) async throws -> Void) async throws {
        // The runner sets TMPDIR inside the local task build directory. Hosted
        // tests also use only their own unique synthetic directory.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStashMonitorTests-\(UUID().uuidString)", isDirectory: true)
        let storage = StorageManager(baseDirectory: directory)
        do {
            try await storage.open()
            try await body(storage, directory)
            await storage.close()
            try FileManager.default.removeItem(at: directory)
        } catch {
            await storage.close()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func testRapidCopyEventuallyCapturedOnceAndFixtureSurvivesReload() async throws {
        try await withFixture { storage, directory in
            let pinnedID = try await storage.insert(type: .text, textContent: "Existing pinned text",
                imageData: nil, sourceBundleId: "test.seed", contentHash: "seed-pin", byteSize: 20)
            try await storage.setPinned(id: pinnedID, pinned: true)
            _ = try await storage.insert(type: .text, textContent: "Existing history text",
                imageData: nil, sourceBundleId: "test.seed", contentHash: "seed-text", byteSize: 21)
            let imageBytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1cAAAAASUVORK5CYII=")!
            let imageID = try await storage.insert(type: .image, textContent: nil,
                imageData: imageBytes, sourceBundleId: "test.seed", contentHash: "seed-image", byteSize: imageBytes.count)
            let seededItems = try await storage.fetchItems(limit: 100, offset: 0)
            let imageItem = try await storage.fetchItem(id: imageID)
            let imageURL = directory.appendingPathComponent("images").appendingPathComponent(imageItem!.imagePath!)

            let pasteboard = Pasteboard()
            let clock = Clock()
            let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { "test.source" })
            pasteboard.copy("First copy")
            await monitor.checkPasteboard()
            clock.date.addTimeInterval(0.3)
            pasteboard.copy("Second rapid copy")
            await monitor.checkPasteboard()
            let deferredItems = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(!deferredItems.contains { $0.textContent == "Second rapid copy" }, "Rapid copy should wait for debounce")
            clock.date.addTimeInterval(0.3)
            await monitor.checkPasteboard()
            let captured = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(captured.filter { $0.textContent == "Second rapid copy" }.count == 1,
                "Second rapid copy must be captured exactly once after debounce")
            for _ in 0..<3 {
                clock.date.addTimeInterval(1)
                await monitor.checkPasteboard()
            }
            let unchanged = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(unchanged.count == 5, "Unchanged polls must not duplicate either copy")
            try expect(unchanged.contains { $0.textContent == "First copy" && $0.sourceBundleId == "test.source" }, "First capture must retain its source")

            await storage.close()
            // Reopening a new actor proves persistence, not an in-memory view.
            let reloaded = StorageManager(baseDirectory: directory)
            do {
                try await reloaded.open()
                for item in seededItems {
                    let actual = try await reloaded.fetchItem(id: item.id)
                    try expect(actual == item, "Preexisting row, pin and metadata must survive reload: \(item.id)")
                }
                let reloadCount = try await reloaded.count()
                try expect(reloadCount == 5, "Both new captures must survive reload")
                try expect(try Data(contentsOf: imageURL) == imageBytes, "Preexisting image bytes must survive")
                await reloaded.close()
            } catch {
                await reloaded.close()
                throw error
            }
        }
    }

    func testRestartSkipsStoppedClipboardAndCapturesNextCopy() async throws {
        try await withFixture { storage, _ in
            let pasteboard = Pasteboard()
            let clock = Clock()
            let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { "test.source" })
            pasteboard.copy("Before initial start")
            monitor.start()
            monitor.stop()
            await monitor.checkPasteboard()
            pasteboard.copy("Captured before stop")
            await monitor.checkPasteboard()
            pasteboard.copy("Copied while stopped")
            monitor.start()
            monitor.stop()
            clock.date.addTimeInterval(1)
            await monitor.checkPasteboard()
            pasteboard.copy("Captured after restart")
            await monitor.checkPasteboard()
            let items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(Set(items.compactMap(\.textContent)) == ["Captured before stop", "Captured after restart"],
                "Restart must skip the current clipboard and capture the next change")
            try expect(!monitor.isRunning, "Stop must invalidate monitoring")
        }
    }

    func testExcludedRapidCopyCannotBecomeEligibleAfterFocusChanges() async throws {
        try await withFixture { storage, _ in
            let pasteboard = Pasteboard()
            let clock = Clock()
            var source = "test.source"
            let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { source })
            pasteboard.copy("Initial allowed copy")
            await monitor.checkPasteboard()
            for sensitiveType in [nil, "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] as [String?] {
                clock.date.addTimeInterval(0.1)
                source = sensitiveType == nil ? "test.ignored" : "test.source"
                pasteboard.copy("Excluded rapid copy")
                if let sensitiveType {
                    pasteboard.types?.append(NSPasteboard.PasteboardType(sensitiveType))
                }
                await monitor.checkPasteboard()
                source = "test.source"
                // Even if the exclusion setting/type disappears, the observed
                // change was rejected and must never be reconsidered.
                pasteboard.types = [.string]
                clock.date.addTimeInterval(1)
                await monitor.checkPasteboard()
            }
            let items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1 && items.first?.textContent == "Initial allowed copy",
                "An excluded rapid copy must stay excluded after focus changes")
        }
    }

    func testSensitiveAndIgnoredCopiesRemainExcluded() async throws {
        try await withFixture { storage, _ in
            let pasteboard = Pasteboard()
            let clock = Clock()
            var source = "test.source"
            let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { source })
            for type in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
                pasteboard.copy("Sensitive content")
                pasteboard.types?.append(NSPasteboard.PasteboardType(type))
                clock.date.addTimeInterval(1)
                await monitor.checkPasteboard()
            }
            pasteboard.copy("Ignored application content")
            source = "test.ignored"
            clock.date.addTimeInterval(1)
            await monitor.checkPasteboard()
            let excludedCount = try await storage.count()
            try expect(excludedCount == 0, "Sensitive and ignored copies must not enter storage")
            source = "test.source"
            pasteboard.copy("Allowed content")
            clock.date.addTimeInterval(1)
            await monitor.checkPasteboard()
            let items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1 && items.first?.textContent == "Allowed content", "Allowed copies must still be captured")
        }
    }
    func testUnpolledExcludedTransitionIsConsumedAndNextAllowedCopySurvives() async throws {
        try await withFixture { storage, _ in
            let seedText = "Transition seed 🙂\r\n"
            let seed = try await storage.insert(type: .text, textContent: seedText,
                imageData: nil, sourceBundleId: "test.seed", contentHash: "transition-seed", byteSize: seedText.utf8.count)
            let original = try await storage.fetchItem(id: seed)
            let board = Pasteboard(), clock = Clock()
            var source = "test.ignored"
            let monitor = ClipboardMonitor(pasteboard: board, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { source }, workspaceNotifications: NotificationCenter())
            monitor.start()
            defer { monitor.stop() }
            let generation = monitor.monitoringGeneration
            board.copy("Excluded text not yet polled")
            source = "test.allowed"
            monitor.handleApplicationActivation(bundleId: "test.allowed", generation: generation)
            clock.date.addTimeInterval(1)
            await monitor.checkPasteboard()
            var items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1, "Leaving excluded app must consume an unpolled copy")

            board.copy("First allowed recovery")
            await monitor.checkPasteboard()
            clock.date.addTimeInterval(1)
            board.copy("Pending text at excluded entry")
            // Event identity wins even while the sampled source is still allowed.
            monitor.handleApplicationActivation(bundleId: "test.ignored", generation: generation)
            monitor.handleApplicationActivation(bundleId: "test.allowed", generation: generation)
            await monitor.checkPasteboard()
            board.copy("Next allowed recovery")
            await monitor.checkPasteboard()
            items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(Set(items.compactMap(\.textContent)) == ["Transition seed 🙂\r\n", "First allowed recovery", "Next allowed recovery"],
                "Both excluded boundaries must stay absent while new allowed copies remain useful")
            let actualSeed = try await storage.fetchItem(id: seed)
            try expect(actualSeed == original, "Existing seed and metadata must remain exact")
        }
    }

    func testObservedExcludedForegroundOverridesStaleAllowedSampleAndRecovers() async throws {
        try await withFixture { storage, _ in
            let board = Pasteboard(), clock = Clock()
            let monitor = ClipboardMonitor(pasteboard: board, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { "test.allowed" }, workspaceNotifications: NotificationCenter())
            monitor.start()
            defer { monitor.stop() }
            let generation = monitor.monitoringGeneration
            // Real activation callbacks use the event's incoming identity because
            // the sampled frontmost app can still name the outgoing allowed app.
            monitor.handleApplicationActivation(bundleId: "test.ignored", generation: generation)
            board.copy("New excluded copy after activation fence")
            await monitor.checkPasteboard()
            let excludedCount = try await storage.count()
            try expect(excludedCount == 0, "Observed excluded foreground must override a stale allowed source sample")

            monitor.handleApplicationActivation(bundleId: "test.allowed", generation: generation)
            board.copy("Allowed recovery A")
            await monitor.checkPasteboard()
            clock.date.addTimeInterval(0.2)
            board.copy("Allowed recovery B pending debounce")
            await monitor.checkPasteboard()
            let beforeDebounce = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(beforeDebounce.count == 1 && beforeDebounce[0].textContent == "Allowed recovery A",
                "Allowed rapid recovery must remain pending during debounce")
            clock.date.addTimeInterval(0.4)
            await monitor.checkPasteboard()
            clock.date.addTimeInterval(1)
            await monitor.checkPasteboard()
            let items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 2 && Set(items.compactMap(\.textContent)) == ["Allowed recovery A", "Allowed recovery B pending debounce"],
                "After leaving excluded foreground, allowed copies must recover exactly once")
        }
    }

    func testStoppedGenerationCannotPollOrConsumeAfterRestart() async throws {
        try await withFixture { storage, _ in
            let board = Pasteboard(), clock = Clock()
            let monitor = ClipboardMonitor(pasteboard: board, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { "test.allowed" }, workspaceNotifications: NotificationCenter())
            monitor.start()
            let old = monitor.monitoringGeneration
            try expect(monitor.hasWorkspaceObserver, "Start must register the injected private center")
            monitor.stop()
            try expect(!monitor.hasWorkspaceObserver, "Stop must remove its workspace observer")
            board.copy("While stopped")
            await monitor.pollIfCurrentGeneration(old)
            monitor.start()
            let current = monitor.monitoringGeneration
            defer { monitor.stop() }
            board.copy("Current generation copy")
            monitor.handleApplicationActivation(bundleId: "test.ignored", generation: old)
            await monitor.pollIfCurrentGeneration(old)
            let beforeCurrent = try await storage.count()
            try expect(beforeCurrent == 0, "A queued old timer cannot capture after restart")
            await monitor.pollIfCurrentGeneration(current)
            var items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1 && items[0].textContent == "Current generation copy",
                "Stale workspace callback must not consume current allowed data")
            monitor.stop()
            try expect(!monitor.hasWorkspaceObserver, "Repeated lifecycle stop must unregister again")
            board.copy("After final stop")
            await monitor.pollIfCurrentGeneration(current)
            items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1 && !monitor.isRunning, "A queued timer cannot capture after Stop")
        }
    }

    func testForegroundBoundaryInvalidatesCapturePreparation() async throws {
        try await withFixture { storage, _ in
            let board = Pasteboard(), clock = Clock()
            let monitor = ClipboardMonitor(pasteboard: board, settings: Settings(), storage: storage,
                now: { clock.date }, sourceBundleId: { "test.allowed" }, workspaceNotifications: NotificationCenter())
            monitor.start()
            defer { monitor.stop() }
            let generation = monitor.monitoringGeneration
            board.copy("Preparation crossing excluded boundary")
            // Deterministic fixture hook at the existing board read seam; no
            // production async hook or claim of real OS timing is introduced.
            board.onRead = {
                monitor.handleApplicationActivation(bundleId: "test.ignored", generation: generation)
                monitor.handleApplicationActivation(bundleId: "test.allowed", generation: generation)
            }
            await monitor.checkPasteboard()
            let rejected = try await storage.count()
            try expect(rejected == 0, "A foreground fence must invalidate unfinished hash/write preparation")
            board.onRead = nil
            board.copy("Allowed after invalidated preparation")
            await monitor.checkPasteboard()
            let items = try await storage.fetchItems(limit: 100, offset: 0)
            try expect(items.count == 1 && items[0].textContent == "Allowed after invalidated preparation",
                "Rejected preparation must not consume or throttle the next allowed copy")
        }
    }

}
