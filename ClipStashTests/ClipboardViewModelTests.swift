import AppKit
import Combine
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

    @MainActor
    func testCopyingHistoryImagePreservesTheBoardUntilItCanWriteCurrentContent() async throws {
        let suffix = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStashImageCopyTests-\(suffix)", isDirectory: true)
        let storage = StorageManager(baseDirectory: directory)
        let board = NSPasteboard(name: NSPasteboard.Name("ClipStashImageCopyTests-\(suffix)"))
        defer {
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        try await storage.open()

        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        var pixel = [70, 140, 210, 255]
        bitmap.setPixel(&pixel, atX: 0, y: 0)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let imageID = try await storage.insert(type: .image, textContent: nil, imageData: png,
            sourceBundleId: "test.generated.window", contentHash: "generated-image", byteSize: png.count)
        let correction = "Corrected screen-share address: https://example.com/training"
        let textID = try await storage.insert(type: .text, textContent: correction, imageData: nil,
            sourceBundleId: "test.generated.notes", contentHash: "generated-text", byteSize: correction.utf8.count)
        let model = ClipboardViewModel(storage: storage, pasteboard: board)
        await model.loadInitial()
        let image = try XCTUnwrap(model.items.first { $0.id == imageID })
        let text = try XCTUnwrap(model.items.first { $0.id == textID })
        let imagePath = try XCTUnwrap(image.imagePath)
        let imageURL = await storage.imageURL(for: imagePath)
        let heldURL = directory.appendingPathComponent("held-image.png")

        let protectedText = "Initial screen-share address: https://example.com/initial"
        board.clearContents()
        XCTAssertTrue(board.setString(protectedText, forType: .string))
        let savedCount = board.changeCount
        try FileManager.default.moveItem(at: imageURL, to: heldURL)
        let missing = await withCheckedContinuation { continuation in
            model.copyToClipboard(image) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(missing)
        XCTAssertEqual(board.changeCount, savedCount)
        XCTAssertEqual(board.string(forType: .string), protectedText)

        try Data("Incomplete image from interrupted restore".utf8).write(to: imageURL)
        let corrupt = await withCheckedContinuation { continuation in
            model.copyToClipboard(image) { continuation.resume(returning: $0) }
        }
        XCTAssertFalse(corrupt)
        XCTAssertEqual(board.changeCount, savedCount)
        XCTAssertEqual(board.string(forType: .string), protectedText)
        try FileManager.default.removeItem(at: imageURL)
        try FileManager.default.moveItem(at: heldURL, to: imageURL)

        let supersededByApp = await withCheckedContinuation { continuation in
            model.copyToClipboard(image) { continuation.resume(returning: $0) }
            board.clearContents()
            XCTAssertTrue(board.setString(correction, forType: .string))
        }
        XCTAssertFalse(supersededByApp)
        XCTAssertEqual(board.string(forType: .string), correction)
        XCTAssertNil(board.data(forType: .tiff))

        let supersededInHistory = await withCheckedContinuation { continuation in
            model.copyToClipboard(image) { continuation.resume(returning: $0) }
            model.copyToClipboard(text)
        }
        XCTAssertFalse(supersededInHistory)
        XCTAssertEqual(board.string(forType: .string), correction)
        XCTAssertNil(board.data(forType: .tiff))

        let retried = await withCheckedContinuation { continuation in
            model.copyToClipboard(image) { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(retried)
        let tiff = try XCTUnwrap(board.data(forType: .tiff))
        let pasted = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        XCTAssertEqual(pasted.pixelsWide, bitmap.pixelsWide)
        XCTAssertEqual(pasted.pixelsHigh, bitmap.pixelsHigh)
        var pastedPixel = [Int](repeating: 0, count: 4)
        pasted.getPixel(&pastedPixel, atX: 0, y: 0)
        XCTAssertEqual(pastedPixel, pixel)
        XCTAssertEqual(try Data(contentsOf: imageURL), png)

        await storage.close()
        let reopened = StorageManager(baseDirectory: directory)
        try await reopened.open()
        let storedItems = try await reopened.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(Set(storedItems), Set([image, text]))
        await reopened.close()
    }
    @MainActor
    func testNewSearchOwnsResultsPaginationAndCopyWhilePreviousReadIsPending() async throws {
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStashSearchTests-\(id)", isDirectory: true)
        let board = NSPasteboard(name: NSPasteboard.Name("ClipStashSearchTests-\(id)"))
        let storage = StorageManager(baseDirectory: directory)
        let started = expectation(description: "Storage actor held for the two search requests")
        let release = DispatchSemaphore(value: 0)
        defer {
            release.signal()
            board.releaseGlobally()
            try? FileManager.default.removeItem(at: directory)
        }
        try await storage.open()
        let oldText = "invoice for a previous rehearsal"
        _ = try await storage.insert(type: .text, textContent: oldText, imageData: nil,
            sourceBundleId: "test.generated.notes", contentHash: "old", byteSize: oldText.utf8.count)
        var expected = Set<Int64>()
        for number in 1...55 {
            let text = "venue access note \(number)"
            let id = try await storage.insert(type: .text, textContent: text, imageData: nil,
                sourceBundleId: "test.generated.notes", contentHash: "new-\(number)", byteSize: text.utf8.count)
            expected.insert(id)
        }

        let model = ClipboardViewModel(storage: storage, pasteboard: board)
        let blocker = Task.detached { await storage.holdSearchTestQueue(started: started, release: release) }
        let gateResult = await XCTWaiter.fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(gateResult, .completed)
        model.searchQuery = "invoice"
        let oldSearch = Task { await model.search() }
        for _ in 0..<200 where !model.isLoading {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.isLoading, "The first query is visibly loading")
        var newerStarted = false
        let observation = model.$items.dropFirst().prefix(1).sink { _ in newerStarted = true }
        model.searchQuery = "venue"
        let newSearch = Task { await model.search() }
        for _ in 0..<200 where !newerStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(newerStarted, "The second query cleared the list before storage was released")
        observation.cancel()
        release.signal()
        await blocker.value
        await oldSearch.value
        await newSearch.value

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.items.count, 50)
        XCTAssertTrue(model.hasMore)
        XCTAssertTrue(model.items.allSatisfy { $0.textContent?.hasPrefix("venue access note") == true })
        model.searchQuery = "invoice"
        await model.loadMore()
        XCTAssertEqual(model.items.count, 50, "Pagination waits while the text field changes before the next search")
        model.searchQuery = "venue"
        await model.loadMore()
        XCTAssertEqual(model.items.count, 55)
        XCTAssertEqual(Set(model.items.map(\.id)), expected)
        XCTAssertFalse(model.hasMore)

        model.selectNext()
        let text = model.selectedItem?.textContent
        model.copySelected()
        XCTAssertNotNil(text)
        XCTAssertEqual(board.string(forType: .string), text)
        XCTAssertNotEqual(board.string(forType: .string), oldText)
        await storage.close()
    }

}

private extension StorageManager {
    func holdSearchTestQueue(started: XCTestExpectation, release: DispatchSemaphore) {
        started.fulfill()
        _ = release.wait(timeout: .now() + .seconds(5))
    }
}
