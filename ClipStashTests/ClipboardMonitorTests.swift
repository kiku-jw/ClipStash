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

        func copy(_ text: String) {
            changeCount += 1
            self.text = text
            types = [.string]
        }

        func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
            dataType == .string ? text : nil
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
}
