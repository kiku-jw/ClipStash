import AppKit
import XCTest
@testable import ClipStash

final class ClipboardViewModelTests: XCTestCase {
    @MainActor
    func testIsolatedHistorySearchPinCopyExportAndReopen() async throws {
        let fixtureID = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStashViewModelTests-\(fixtureID)", isDirectory: true)
        let databaseDirectory = directory.appendingPathComponent("database", isDirectory: true)
        let storage = StorageManager(baseDirectory: databaseDirectory)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipStashViewModelTests-\(fixtureID)"))
        var reopenedStorage: StorageManager?
        defer { pasteboard.releaseGlobally() }

        do {
            try await storage.open()
            let targetText = "Generated apricot fixture \(fixtureID)"
            let otherText = "Generated blueberry fixture \(fixtureID)"
            let targetID = try await storage.insert(type: .text, textContent: targetText,
                imageData: nil, sourceBundleId: "test.generated.apricot",
                contentHash: "apricot-\(fixtureID)", byteSize: targetText.utf8.count)
            let otherID = try await storage.insert(type: .text, textContent: otherText,
                imageData: nil, sourceBundleId: "test.generated.blueberry",
                contentHash: "blueberry-\(fixtureID)", byteSize: otherText.utf8.count)

            let model = ClipboardViewModel(storage: storage, pasteboard: pasteboard)
            await model.loadInitial()
            XCTAssertNil(model.error)
            XCTAssertEqual(Set(model.items.map(\.id)), Set([targetID, otherID]))
            XCTAssertFalse(model.hasMore)

            model.searchQuery = "apricot"
            await model.search()
            XCTAssertNil(model.error)
            XCTAssertEqual(model.items.map(\.id), [targetID])
            model.selectNext()
            XCTAssertEqual(model.selectedItem?.id, targetID)
            await model.togglePinnedSelected()
            XCTAssertNil(model.error)
            XCTAssertEqual(model.selectedItem?.pinned, true)
            model.copySelected()
            XCTAssertEqual(pasteboard.string(forType: .string), targetText)

            model.searchQuery = ""
            await model.search()
            XCTAssertNil(model.error)
            XCTAssertEqual(model.items.map(\.id), [targetID, otherID])
            XCTAssertEqual(model.items.map(\.textContent), [targetText, otherText])
            XCTAssertEqual(model.items.map(\.pinned), [true, false])
            let expectedHistory = model.items

            let result = try await ExportService(storage: storage).export(
                scope: .lastN(10), format: .markdown, includeImageRefs: false,
                destinationDir: directory.appendingPathComponent("export", isDirectory: true))
            XCTAssertEqual(result.itemCount, 2)
            let exportFile = try XCTUnwrap(result.files.first)
            XCTAssertEqual(result.files.count, 1)
            let exported = try String(contentsOf: exportFile, encoding: .utf8)
            XCTAssertTrue(exported.contains(targetText))
            XCTAssertTrue(exported.contains(otherText))

            await storage.close()
            let freshStorage = StorageManager(baseDirectory: databaseDirectory)
            reopenedStorage = freshStorage
            try await freshStorage.open()
            let reopenedModel = ClipboardViewModel(storage: freshStorage, pasteboard: pasteboard)
            await reopenedModel.loadInitial()
            XCTAssertNil(reopenedModel.error)
            XCTAssertEqual(reopenedModel.items, expectedHistory)
            reopenedModel.selectNext()
            XCTAssertEqual(reopenedModel.selectedItem?.id, targetID)
            reopenedModel.copySelected()
            XCTAssertEqual(pasteboard.string(forType: .string), targetText)

            await freshStorage.close()
            try FileManager.default.removeItem(at: directory)
        } catch {
            await storage.close()
            if let reopenedStorage { await reopenedStorage.close() }
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
