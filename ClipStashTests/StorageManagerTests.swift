import AppKit
import XCTest
import SQLite3
@testable import ClipStash

final class StorageManagerTests: XCTestCase {
    
    var tempDBPath: URL!
    var storage: StorageManager!
    
    override func setUp() async throws {
        // Use a temporary database for testing
        tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDBPath, withIntermediateDirectories: true)
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
    }
    
    override func tearDown() async throws {
        await storage.close()
        storage = nil
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDBPath)
    }
    
    // MARK: - Tests
    
    func testOpenDatabase() async throws {
        try await storage.open()
        // Should not throw
    }

    func testCannotOpenDirectoryRepeatedlyAndRetrySameActorAfterRepair() async throws {
        await storage.close()
        let databaseURL = tempDBPath.appendingPathComponent("clipstash.db")
        try FileManager.default.removeItem(at: databaseURL)
        try FileManager.default.createDirectory(at: databaseURL, withIntermediateDirectories: false)
        let sentinelURL = databaseURL.appendingPathComponent("sentinel")
        let sentinel = Data("Keep this test fixture intact".utf8)
        try sentinel.write(to: sentinelURL)

        for _ in 0..<2 {
            do {
                try await storage.open()
                XCTFail("Expected SQLITE_CANTOPEN for a directory at the database path")
            } catch StorageError.cannotOpenDatabase(let message) {
                XCTAssertEqual(message, "unable to open database file")
            }
            XCTAssertEqual(try Data(contentsOf: sentinelURL), sentinel)
        }

        // Only the test repairs its blocker; production must leave it untouched.
        try FileManager.default.removeItem(at: databaseURL)
        try await storage.open()
        let count = try await storage.count()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try fixtureInteger("PRAGMA user_version"), 2)
    }

    func testCorruptDatabaseRepeatedlyFailsWithoutChangingBytesAndRetriesAfterRepair() async throws {
        await storage.close()
        let databaseURL = tempDBPath.appendingPathComponent("clipstash.db")
        let corruptBytes = Data("This is an intentionally invalid SQLite fixture.\n".utf8)
        try corruptBytes.write(to: databaseURL)

        for _ in 0..<2 {
            do {
                try await storage.open()
                XCTFail("Expected initialization to reject corrupt database bytes")
            } catch StorageError.executeFailed(let message) {
                XCTAssertEqual(message, "file is not a database")
            }
            XCTAssertEqual(try Data(contentsOf: databaseURL), corruptBytes)
        }

        try FileManager.default.removeItem(at: databaseURL)
        try await storage.open()
        let count = try await storage.count()
        XCTAssertEqual(count, 0)
        XCTAssertEqual(try fixtureInteger("PRAGMA user_version"), 2)
    }

    func testMigrationFailureRetriesSameActorAndPreservesPinnedNULText() async throws {
        let text = "Pinned before\u{0000}after 🙂\r\n"
        let seedID = try await storage.insert(type: .text, textContent: text,
            imageData: nil, sourceBundleId: "test.migration", contentHash: "migration-seed",
            byteSize: text.utf8.count)
        try await storage.setPinned(id: seedID, pinned: true)
        let fetchedSeed = try await storage.fetchItem(id: seedID)
        let seed = try XCTUnwrap(fetchedSeed)
        await storage.close()
        // WAL setup and FTS detection succeed before this v1 -> v2 migration fails.
        try executeFixtureSQL("""
            DROP INDEX idx_items_sourceBundleId;
            CREATE TABLE idx_items_sourceBundleId (blocker INTEGER);
            PRAGMA user_version = 1;
            """)

        for _ in 0..<2 {
            do {
                try await storage.open()
                XCTFail("Expected the fixture table to block the migration index")
            } catch StorageError.executeFailed(let message) {
                XCTAssertTrue(message.contains("idx_items_sourceBundleId"), message)
            }
            XCTAssertEqual(try fixtureInteger("PRAGMA user_version"), 1)
        }

        try executeFixtureSQL("DROP TABLE idx_items_sourceBundleId")
        try await storage.open()
        XCTAssertEqual(try fixtureInteger("PRAGMA user_version"), 2)
        XCTAssertEqual(try fixtureInteger("""
            SELECT count(*) FROM sqlite_master
            WHERE type = 'index' AND name = 'idx_items_sourceBundleId' AND tbl_name = 'items'
            """), 1)
        let reloaded = try await storage.fetchItem(id: seedID)
        let count = try await storage.count()
        XCTAssertEqual(reloaded, seed)
        XCTAssertEqual(reloaded?.textContent.map { Data($0.utf8) }, Data(text.utf8))
        XCTAssertEqual(count, 1)
    }
    
    func testInsertAndFetch() async throws {
        try await storage.open()
        
        let id = try await storage.insert(
            type: .text,
            textContent: "Hello, World!",
            imageData: nil,
            sourceBundleId: "com.apple.Safari",
            contentHash: "testhash123",
            byteSize: 13
        )
        
        XCTAssertGreaterThan(id, 0)
        
        let items = try await storage.fetchItems(limit: 10, offset: 0)
        XCTAssertFalse(items.isEmpty)
        
        let item = items.first { $0.id == id }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.textContent, "Hello, World!")
        XCTAssertEqual(item?.sourceBundleId, "com.apple.Safari")
    }
    
    func testDeduplication() async throws {
        try await storage.open()
        
        let hash = "uniquehash456"
        
        // First insert
        _ = try await storage.insert(
            type: .text,
            textContent: "Duplicate content",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: hash,
            byteSize: 17
        )
        
        // Check exists
        let exists = try await storage.exists(contentHash: hash)
        XCTAssertTrue(exists)
        
        // Non-existent hash
        let notExists = try await storage.exists(contentHash: "nonexistent")
        XCTAssertFalse(notExists)
    }

    func testTextUTF8BytesIncludingNULSurviveFetchExportAndReopen() async throws {
        let seedID = try await storage.insert(type: .text, textContent: "Existing pinned history",
            imageData: nil, sourceBundleId: "test.seed", contentHash: "seed", byteSize: 23)
        try await storage.setPinned(id: seedID, pinned: true)
        let seed = try await storage.fetchItem(id: seedID)
        let samples = ["before\u{0000}after 🙂\r\n", "\u{0000}leading", "trailing\u{0000}", "", "e\u{0301}\n"]
        var ids: [Int64] = []
        for (index, text) in samples.enumerated() {
            let id = try await storage.insert(type: .text, textContent: text, imageData: nil,
                sourceBundleId: "test.source", contentHash: "bytes-\(index)", byteSize: text.utf8.count)
            ids.append(id)
        }

        // A new actor exercises the disk path; existing rows must remain exact.
        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let reloadedSeed = try await storage.fetchItem(id: seedID)
        XCTAssertEqual(reloadedSeed, seed)
        let items = try await storage.fetchItems(limit: 100, offset: 0)
        let exported = try await storage.fetchForExport(ids: ids)
        XCTAssertEqual(items.count, samples.count + 1)
        XCTAssertEqual(exported.count, samples.count)
        for (index, pair) in zip(ids, samples).enumerated() {
            let (id, text) = pair
            let fetched = try await storage.fetchItem(id: id)
            for item in [fetched, items.first { $0.id == id }, exported.first { $0.id == id }] {
                XCTAssertEqual(item?.textContent.map { Data($0.utf8) }, Data(text.utf8))
                XCTAssertEqual(item?.byteSize, text.utf8.count)
                XCTAssertEqual(item?.contentHash, "bytes-\(index)")
            }
        }
    }
    
    @MainActor
    func testHistoryAndSearchPreferNewerCopiesWithinOneSecond() async throws {
        let sameSecond: Int64 = 1_794_000_000
        let source = "test.same-second-history"
        let pinnedText = "Pinned venue directions"
        let pinned = try await storage.insert(type: .text, textContent: pinnedText, imageData: nil,
            sourceBundleId: source, contentHash: "same-second-pinned", byteSize: pinnedText.utf8.count)
        try await storage.setPinned(id: pinned, pinned: true)

        var ids: [Int64] = []
        for number in 1...55 {
            let text = "Venue access code revision \(number)"
            let id = try await storage.insert(type: .text, textContent: text, imageData: nil,
                sourceBundleId: source, contentHash: "same-second-\(number)", byteSize: text.utf8.count)
            ids.append(id)
        }
        try executeFixtureSQL("UPDATE items SET createdAt = \(sameSecond)")
        let expected = [pinned] + Array(ids.reversed())

        let history = try await storage.fetchItems(limit: 50, offset: 0)
        let historyTail = try await storage.fetchItems(limit: 50, offset: 50)
        XCTAssertEqual((history + historyTail).map(\.id), expected)
        let chronological = try await storage.fetchItems(limit: 56, offset: 0, pinnedFirst: false)
        XCTAssertEqual(chronological.map(\.id), Array(ids.reversed()) + [pinned])

        let board = NSPasteboard(name: NSPasteboard.Name("ClipStashHistoryOrderTest-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let viewModel = ClipboardViewModel(storage: storage, pasteboard: board)
        viewModel.searchQuery = "venue"
        await viewModel.search()
        XCTAssertEqual(viewModel.items.map(\.id), Array(expected.prefix(50)))
        await viewModel.loadMore()
        XCTAssertEqual(viewModel.items.map(\.id), expected)
        XCTAssertFalse(viewModel.hasMore)
        viewModel.selectNext() // Pinned directions.
        viewModel.selectNext() // Latest ordinary match.
        viewModel.copySelected()
        XCTAssertEqual(board.string(forType: .string), "Venue access code revision 55")

        await storage.close()
        let reopened = StorageManager(baseDirectory: tempDBPath)
        try await reopened.open()
        let reopenedHistory = try await reopened.fetchItems(limit: 56, offset: 0)
        XCTAssertEqual(reopenedHistory.map(\.id), expected)
        XCTAssertTrue(reopenedHistory.first?.pinned == true)
        await reopened.close()
    }

    func testLast50PrefersTheNewerCopyAtASameSecondBoundary() async throws {
        let oldCopy = "Boundary copy: initial invoice reference"
        let newCopy = "Boundary copy: corrected invoice reference"
        let samples = [oldCopy, newCopy] + (1...49).map { "Generated recent note \($0)" }
        var ids: [Int64] = []
        for (index, text) in samples.enumerated() {
            let id = try await storage.insert(type: .text, textContent: text, imageData: nil,
                sourceBundleId: "test.latest-export", contentHash: "fixture-\(index)",
                byteSize: text.utf8.count)
            ids.append(id)
        }

        // The two oldest copies share one timestamp second. The export limit
        // must keep the second copy, which has the later insertion ID.
        try executeFixtureSQL("""
            UPDATE items SET createdAt = CASE
                WHEN id IN (\(ids[0]), \(ids[1])) THEN 1794000000
                ELSE 1794000000 + id
            END
            """)
        let before = try await storage.fetchForExport()
        let export = try await ExportService(storage: storage).export(
            scope: .lastN(50), format: .plainText,
            destinationDir: tempDBPath.appendingPathComponent("generated-export")
        )
        XCTAssertEqual(export.itemCount, 50)
        XCTAssertEqual(export.files.count, 1)
        let file = try XCTUnwrap(export.files.first)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(text.contains(newCopy), "Export omitted the newer copy")
        XCTAssertFalse(text.contains(oldCopy), "Export included the older copy instead")
        for recent in samples.dropFirst(2) {
            XCTAssertTrue(text.contains(recent))
        }

        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let reopened = try await storage.fetchForExport()
        XCTAssertEqual(reopened.count, 51)
        XCTAssertEqual(reopened, before)
    }

    // Generated 2x2 PNG; no user clipboard data is used by these fixtures.
    func testClearKeepsImageReferencedByPinnedHistory() async throws {
        let fixture = generatedPNG
        let shared = try await storage.insert(type: .image, textContent: nil, imageData: fixture,
            sourceBundleId: "test.clear", contentHash: "shared-image", byteSize: fixture.count)
        let pinned = try await storage.insert(type: .image, textContent: nil, imageData: nil,
            sourceBundleId: "test.clear", contentHash: "pinned-reference", byteSize: fixture.count)
        let discard = try await storage.insert(type: .image, textContent: nil, imageData: fixture,
            sourceBundleId: "test.clear", contentHash: "unreferenced-image", byteSize: fixture.count)
        try await storage.setPinned(id: pinned, pinned: true)
        try executeFixtureSQL("UPDATE items SET imagePath = (SELECT imagePath FROM items WHERE id = \(shared)) WHERE id = \(pinned)")
        let sharedRecord = try await storage.fetchItem(id: shared)
        let discardRecord = try await storage.fetchItem(id: discard)
        let kept = await storage.imageURL(for: try XCTUnwrap(sharedRecord?.imagePath))
        let removed = await storage.imageURL(for: try XCTUnwrap(discardRecord?.imagePath))

        try await storage.clearAll(keepPinned: true)
        await storage.close()
        let reopened = StorageManager(baseDirectory: tempDBPath)
        try await reopened.open()
        let rows = try await reopened.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(rows.map(\.id), [pinned])
        XCTAssertTrue(rows.first?.pinned == true)
        XCTAssertEqual(try Data(contentsOf: kept), fixture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        try await reopened.clearAll(keepPinned: false)
        let empty = try await reopened.count()
        XCTAssertEqual(empty, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path))
        await reopened.close()
    }

    func testDeletingOneImageReferenceKeepsThePinnedCopyAfterReopen() async throws {
        try await assertSharedImageSurvivesRemoval { removedID in
            try await self.storage.delete(id: removedID)
        }
    }

    func testEvictingOneImageReferenceKeepsThePinnedCopyAfterReopen() async throws {
        try await assertSharedImageSurvivesRemoval { _ in
            try await self.storage.evict(limit: 0)
        }
    }

    private func assertSharedImageSurvivesRemoval(
        _ remove: (Int64) async throws -> Void
    ) async throws {
        let fixture = generatedPNG
        let original = try await storage.insert(type: .image, textContent: nil, imageData: fixture,
            sourceBundleId: "test.history", contentHash: "original-image", byteSize: fixture.count)
        let pinned = try await storage.insert(type: .image, textContent: nil, imageData: nil,
            sourceBundleId: "test.history", contentHash: "pinned-reference", byteSize: fixture.count)
        try await storage.setPinned(id: pinned, pinned: true)
        try executeFixtureSQL("UPDATE items SET imagePath = (SELECT imagePath FROM items WHERE id = \(original)) WHERE id = \(pinned)")
        let originalRecord = try await storage.fetchItem(id: original)
        let imageURL = await storage.imageURL(for: try XCTUnwrap(originalRecord?.imagePath))

        try await remove(original)
        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let rows = try await storage.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(rows.map(\.id), [pinned])
        XCTAssertTrue(rows.first?.pinned == true)
        let retained = try? Data(contentsOf: imageURL)
        XCTAssertEqual(retained, fixture)
        if let retained {
            XCTAssertNotNil(NSImage(data: retained))
        }

        try await storage.delete(id: pinned)
        let count = try await storage.count()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageURL.path))
    }

    private var generatedPNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGO4YxQFRAwQCgApdgWhAEbY9wAAAABJRU5ErkJggg==")!
    }

    private func executeFixtureSQL(_ sql: String) throws {
        var db: OpaquePointer?
        let result = sqlite3_open(tempDBPath.appendingPathComponent("clipstash.db").path, &db)
        defer { sqlite3_close(db) }
        guard result == SQLITE_OK else { throw StorageError.cannotOpenDatabase("Fixture database") }
        var message: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &message) != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? "Fixture SQL failed"
            sqlite3_free(message)
            throw StorageError.executeFailed(detail)
        }
    }

    private func fixtureInteger(_ sql: String) throws -> Int {
        var db: OpaquePointer?
        let result = sqlite3_open(tempDBPath.appendingPathComponent("clipstash.db").path, &db)
        defer { sqlite3_close(db) }
        guard result == SQLITE_OK else { throw StorageError.cannotOpenDatabase("Fixture database") }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else {
            throw StorageError.executeFailed("Fixture integer query failed")
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func imageFiles() throws -> Set<URL> {
        Set(try FileManager.default.contentsOfDirectory(
            at: tempDBPath.appendingPathComponent("images"), includingPropertiesForKeys: nil))
    }

    func testFailedImageInsertRemovesOnlyUnreferencedAttemptImage() async throws {
        let image = generatedPNG
        let seedID = try await storage.insert(type: .image, textContent: nil, imageData: image,
            sourceBundleId: "test.seed", contentHash: "seed-image", byteSize: image.count)
        try await storage.setPinned(id: seedID, pinned: true)
        let seed = try await storage.fetchItem(id: seedID)
        let seedURL = await storage.imageURL(for: try XCTUnwrap(seed?.imagePath))
        let originalFiles = try imageFiles()
        try executeFixtureSQL("""
            CREATE TRIGGER fixture_reject_image BEFORE INSERT ON items
            WHEN NEW.sourceBundleId = 'test.rejected'
            BEGIN SELECT RAISE(ABORT, 'fixture image rejection'); END;
            """)
        do {
            _ = try await storage.insert(type: .image, textContent: nil, imageData: image,
                sourceBundleId: "test.rejected", contentHash: "rejected-image", byteSize: image.count)
            XCTFail("Expected SQLite insertion failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Insert failed: fixture image rejection")
        }
        XCTAssertEqual(try imageFiles(), originalFiles)
        let afterFailure = try await storage.fetchItem(id: seedID)
        let count = try await storage.count()
        let rejectedExists = try await storage.exists(contentHash: "rejected-image")
        XCTAssertEqual(afterFailure, seed)
        XCTAssertEqual(count, 1)
        XCTAssertFalse(rejectedExists)
        XCTAssertEqual(try Data(contentsOf: seedURL), image)

        let successID = try await storage.insert(type: .image, textContent: nil, imageData: image,
            sourceBundleId: "test.success", contentHash: "success-image", byteSize: image.count)
        let success = try await storage.fetchItem(id: successID)
        let successURL = await storage.imageURL(for: try XCTUnwrap(success?.imagePath))
        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let reloaded = try await storage.fetchItem(id: successID)
        XCTAssertEqual(reloaded, success)
        XCTAssertEqual(try Data(contentsOf: successURL), image)
        try await storage.delete(id: successID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: successURL.path))
        try await storage.clearAll(keepPinned: true)
        let retainedSeed = try await storage.fetchItem(id: seedID)
        XCTAssertEqual(retainedSeed, seed)
        XCTAssertEqual(try Data(contentsOf: seedURL), image)
        try await storage.clearAll(keepPinned: false)
        XCTAssertTrue(try imageFiles().isEmpty)
    }

    func testImageInsertErrorPreservesImageReferencedByPersistedRow() async throws {
        let image = generatedPNG
        try executeFixtureSQL("""
            CREATE TRIGGER fixture_fail_after_image AFTER INSERT ON items
            BEGIN SELECT RAISE(FAIL, 'fixture persisted image'); END;
            """)
        do {
            _ = try await storage.insert(type: .image, textContent: nil, imageData: image,
                sourceBundleId: "test.persisted", contentHash: "persisted-image", byteSize: image.count)
            XCTFail("Expected SQLite error after insertion")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Insert failed: fixture persisted image")
        }
        let rows = try await storage.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(rows.count, 1)
        let item = try XCTUnwrap(rows.first)
        let url = await storage.imageURL(for: try XCTUnwrap(item.imagePath))
        XCTAssertEqual(try Data(contentsOf: url), image)
        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let reloaded = try await storage.fetchItem(id: item.id)
        XCTAssertEqual(reloaded, item)
        XCTAssertEqual(try Data(contentsOf: url), image)
    }

    func testImageInsertErrorPreservesFileWhenReferenceLookupFails() async throws {
        let image = generatedPNG
        let seedID = try await storage.insert(type: .image, textContent: nil, imageData: image,
            sourceBundleId: "test.seed", contentHash: "unknown-seed", byteSize: image.count)
        try await storage.setPinned(id: seedID, pinned: true)
        let seed = try await storage.fetchItem(id: seedID)
        let originalFiles = try imageFiles()
        // INSERT and the cleanup reference query encounter a real missing table.
        try executeFixtureSQL("ALTER TABLE items RENAME TO fixture_saved_items")
        do {
            _ = try await storage.insert(type: .image, textContent: nil, imageData: image,
                sourceBundleId: "test.unknown", contentHash: "unknown-image", byteSize: image.count)
            XCTFail("Expected missing-table insertion failure")
        } catch {
            // SQLite may discover the external schema change during prepare or step.
            XCTAssertTrue(["SQL prepare failed: no such table: items", "Insert failed: no such table: items"]
                .contains(error.localizedDescription), error.localizedDescription)
        }
        let addedFiles = try imageFiles().subtracting(originalFiles)
        XCTAssertEqual(addedFiles.count, 1)
        let preservedURL = try XCTUnwrap(addedFiles.first)
        XCTAssertEqual(try Data(contentsOf: preservedURL), image)
        try executeFixtureSQL("ALTER TABLE fixture_saved_items RENAME TO items")
        await storage.close()
        storage = StorageManager(baseDirectory: tempDBPath)
        try await storage.open()
        let reloadedSeed = try await storage.fetchItem(id: seedID)
        XCTAssertEqual(reloadedSeed, seed)
        XCTAssertEqual(try Data(contentsOf: preservedURL), image)
    }

    func testEviction() async throws {
        try await storage.open()
        
        // Clear existing data
        try await storage.clearAll(keepPinned: false)
        
        // Insert 10 items
        for i in 0..<10 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 6
            )
        }
        
        let countBefore = try await storage.count()
        XCTAssertEqual(countBefore, 10)
        
        // Evict to limit 5
        try await storage.evict(limit: 5)
        
        let countAfter = try await storage.countUnpinned()
        XCTAssertEqual(countAfter, 5)
    }
    
    func testPinned() async throws {
        try await storage.open()
        
        let id = try await storage.insert(
            type: .text,
            textContent: "Pin me",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "pinhash",
            byteSize: 6
        )
        
        // Toggle pinned
        try await storage.togglePinned(id: id)
        
        let item = try await storage.fetchItem(id: id)
        XCTAssertTrue(item?.pinned ?? false)
        
        // Toggle again
        try await storage.togglePinned(id: id)
        
        let item2 = try await storage.fetchItem(id: id)
        XCTAssertFalse(item2?.pinned ?? true)
    }
    
    func testSearch() async throws {
        try await storage.open()
        
        // Clear and insert test data
        try await storage.clearAll(keepPinned: false)
        
        _ = try await storage.insert(
            type: .text,
            textContent: "The quick brown fox",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "searchhash1",
            byteSize: 19
        )
        
        _ = try await storage.insert(
            type: .text,
            textContent: "Lazy dog sleeps",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "searchhash2",
            byteSize: 15
        )
        
        // Search for "fox"
        let results = try await storage.search(query: "fox", limit: 10, offset: 0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "The quick brown fox")
        
        // Search for "dog"
        let results2 = try await storage.search(query: "dog", limit: 10, offset: 0)
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(results2.first?.textContent, "Lazy dog sleeps")
    }

    func testSearchWithEmbeddedQuote() async throws {
        try await storage.open()
        try await storage.clearAll(keepPinned: false)

        _ = try await storage.insert(
            type: .text,
            textContent: "A fox\" text",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "quotedsearchhash",
            byteSize: 12
        )

        // A quote in the query used to produce an unterminated FTS5 phrase.
        let results = try await storage.search(query: "fox\"", limit: 10, offset: 0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "A fox\" text")
    }

    func testPaging() async throws {
        try await storage.open()
        
        // Clear existing data
        try await storage.clearAll(keepPinned: false)
        
        // Insert 20 items
        for i in 0..<20 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Page item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "pagehash\(i)",
                byteSize: 12
            )
        }
        
        // Fetch first page
        let page1 = try await storage.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(page1.count, 10)
        
        // Fetch second page
        let page2 = try await storage.fetchItems(limit: 10, offset: 10)
        XCTAssertEqual(page2.count, 10)
        
        // Ensure no overlap
        let page1Ids = Set(page1.map { $0.id })
        let page2Ids = Set(page2.map { $0.id })
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
    
    func testDelete() async throws {
        try await storage.open()
        
        let id = try await storage.insert(
            type: .text,
            textContent: "Delete me",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "deletehash",
            byteSize: 9
        )
        
        // Verify exists
        let item = try await storage.fetchItem(id: id)
        XCTAssertNotNil(item)
        
        // Delete
        try await storage.delete(id: id)
        
        // Verify deleted
        let deleted = try await storage.fetchItem(id: id)
        XCTAssertNil(deleted)
    }
}
