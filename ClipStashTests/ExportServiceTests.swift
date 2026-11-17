import XCTest
import AppKit
import SQLite3
@testable import ClipStash

final class ExportServiceTests: XCTestCase {
    
    var tempExportDir: URL!
    var storage: StorageManager!
    var service: ExportService!
    
    override func setUp() async throws {
        tempExportDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipStashExportTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempExportDir, withIntermediateDirectories: true)
        
        storage = StorageManager(baseDirectory: tempExportDir.appendingPathComponent("database", isDirectory: true))
        service = ExportService(storage: storage)
        try await storage.open()
    }
    
    override func tearDown() async throws {
        await storage.close()
        service = nil
        storage = nil
        // Only this test's newly created directory may be removed.
        try? FileManager.default.removeItem(at: tempExportDir)
    }
    
    // MARK: - Tests
    
    func testMarkdownExport() async throws {
        // Clear and insert test data
        try await storage.clearAll(keepPinned: false)
        
        _ = try await storage.insert(
            type: .text,
            textContent: "Test export content",
            imageData: nil,
            sourceBundleId: "com.test.app",
            contentHash: "exporthash1",
            byteSize: 19
        )
        
        let result = try await service.export(
            scope: .lastN(10),
            format: .markdown,
            includeImageRefs: false,
            destinationDir: tempExportDir
        )
        
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.itemCount, 1)
        
        // Verify file content
        let content = try String(contentsOf: result.files[0], encoding: .utf8)
        XCTAssertTrue(content.contains("Clipboard Export"))
        XCTAssertTrue(content.contains("Test export content"))
        XCTAssertTrue(content.contains("com.test.app"))
    }
    
    func testPlainTextExport() async throws {
        try await storage.clearAll(keepPinned: false)
        
        _ = try await storage.insert(
            type: .text,
            textContent: "Plain text export",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "plaintexthash",
            byteSize: 17
        )
        
        let result = try await service.export(
            scope: .lastN(10),
            format: .plainText,
            includeImageRefs: false,
            destinationDir: tempExportDir
        )
        
        XCTAssertEqual(result.files.count, 1)
        
        let file = result.files[0]
        XCTAssertTrue(file.pathExtension == "txt")
        
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(content.contains("Plain text export"))
    }

    func testRepeatedExportsKeepExistingParentFile() async throws {
        try await storage.clearAll(keepPinned: false)

        _ = try await storage.insert(
            type: .text,
            textContent: "Repeated export content",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "repeated-export-hash",
            byteSize: 24
        )

        // This represents an unrelated export already present in the folder
        // selected by the user. Each new export is given its own child folder
        // by the UI, so this file must remain byte-for-byte unchanged.
        let existingParentFile = tempExportDir.appendingPathComponent("export.md")
        let existingContent = "Keep this existing export.\n"
        try existingContent.write(to: existingParentFile, atomically: true, encoding: .utf8)

        for _ in 1...2 {
            let destinationDir = await MainActor.run {
                ExportDestinationPicker.uniqueExportDirectory(inside: tempExportDir)
            }
            let result = try await service.export(
                scope: .lastN(10),
                format: .markdown,
                includeImageRefs: false,
                destinationDir: destinationDir
            )

            XCTAssertEqual(result.files.count, 1)
            XCTAssertTrue(destinationDir.lastPathComponent.hasPrefix("ClipStash_Export_"))
            XCTAssertTrue(result.files.allSatisfy {
                $0.deletingLastPathComponent().standardizedFileURL == destinationDir.standardizedFileURL
            })
            XCTAssertEqual(
                try String(contentsOf: existingParentFile, encoding: .utf8),
                existingContent
            )
        }
    }

    func testAutoSplit() async throws {
        try await storage.clearAll(keepPinned: false)
        
        // Insert items with many words to trigger splitting
        // Target is ~400K words, so we need to generate enough content
        // Each item: 100,000 words (100K words × 5 items = 500K words > 400K limit)
        let manyWords = (0..<100_000).map { "word\($0)" }.joined(separator: " ")
        
        for i in 0..<5 {
            _ = try await storage.insert(
                type: .text,
                textContent: "\(manyWords) Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "largehash\(i)",
                byteSize: manyWords.utf8.count
            )
        }
        
        let result = try await service.export(
            scope: .lastN(100),
            format: .markdown,
            includeImageRefs: false,
            destinationDir: tempExportDir
        )
        
        // Should have created multiple files due to auto-split (500K words / 400K limit = 2+ files)
        XCTAssertGreaterThan(result.files.count, 1)
    }
    
    func testPinnedOnlyExport() async throws {
        try await storage.clearAll(keepPinned: false)
        
        // Insert regular item
        _ = try await storage.insert(
            type: .text,
            textContent: "Not pinned",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "notpinned",
            byteSize: 10
        )
        
        // Insert and pin item
        let pinnedId = try await storage.insert(
            type: .text,
            textContent: "Pinned item",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "pinnedhash",
            byteSize: 11
        )
        try await storage.setPinned(id: pinnedId, pinned: true)
        
        let result = try await service.export(
            scope: .pinnedOnly,
            format: .markdown,
            includeImageRefs: false,
            destinationDir: tempExportDir
        )
        
        XCTAssertEqual(result.itemCount, 1)
        
        let content = try String(contentsOf: result.files[0], encoding: .utf8)
        XCTAssertTrue(content.contains("Pinned item"))
        XCTAssertFalse(content.contains("Not pinned"))
    }
    
    func testEmptyExportThrows() async throws {
        try await storage.clearAll(keepPinned: false)
        
        do {
            _ = try await service.export(
                scope: .pinnedOnly, // No pinned items
                format: .markdown,
                includeImageRefs: false,
                destinationDir: tempExportDir
            )
            XCTFail("Should have thrown noItemsToExport")
        } catch ExportError.noItemsToExport {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    // MARK: - Image Integrity

    private func makePNG(red: Int, blue: Int) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32
        ))
        var rgba = [red, 0, blue, 255]
        for y in 0..<2 {
            for x in 0..<2 { bitmap.setPixel(&rgba, atX: x, y: y) }
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func insertImage(_ data: Data?, source: String) async throws -> Int64 {
        try await storage.insert(type: .image, textContent: nil, imageData: data,
            sourceBundleId: source, contentHash: source, byteSize: data?.count ?? 0)
    }

    private func imageReferences(in markdownURL: URL) throws -> [String] {
        try String(contentsOf: markdownURL, encoding: .utf8)
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("[Image] images/") }
            .map { String($0.dropFirst("[Image] ".count)) }
    }

    private func assertImages(_ result: ExportService.ExportResult, expected: [String: Data]) throws {
        XCTAssertEqual(result.itemCount, expected.count)
        XCTAssertEqual(result.files.count, 1)
        let markdownURL = try XCTUnwrap(result.files.first)
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let refs = try imageReferences(in: markdownURL)
        XCTAssertEqual(refs.count, expected.count)
        XCTAssertEqual(Set(refs).count, expected.count)
        for (source, original) in expected {
            let entry = try XCTUnwrap(markdown.components(separatedBy: "## ")
                .first { $0.contains("(\(source))") })
            let refLine = try XCTUnwrap(entry.components(separatedBy: .newlines)
                .first { $0.hasPrefix("[Image] images/") })
            let url = markdownURL.deletingLastPathComponent()
                .appendingPathComponent(String(refLine.dropFirst("[Image] ".count)))
            let copied = try Data(contentsOf: url)
            XCTAssertEqual(copied, original)
            let decoded = try XCTUnwrap(NSBitmapImageRep(data: copied))
            let expectedBitmap = try XCTUnwrap(NSBitmapImageRep(data: original))
            XCTAssertEqual(decoded.pixelsWide, 2)
            XCTAssertEqual(decoded.pixelsHigh, 2)
            for y in 0..<2 {
                for x in 0..<2 {
                    var actual = [Int](repeating: 0, count: 4)
                    var expectedPixel = actual
                    decoded.getPixel(&actual, atX: x, y: y)
                    expectedBitmap.getPixel(&expectedPixel, atX: x, y: y)
                    XCTAssertEqual(actual, expectedPixel)
                }
            }
        }
    }

    private func assertPlainTextImages(_ result: ExportService.ExportResult, expected: [Int64: Data], itemCount: Int) throws {
        XCTAssertEqual(result.itemCount, itemCount)
        XCTAssertEqual(result.files.count, 1)
        let textURL = try XCTUnwrap(result.files.first)
        XCTAssertEqual(textURL.pathExtension, "txt")
        let refs = try imageReferences(in: textURL)
        XCTAssertEqual(refs.count, expected.count)
        XCTAssertEqual(Set(refs).count, expected.count)
        for (id, original) in expected {
            let relativePath = try XCTUnwrap(refs.first { $0.hasSuffix("_\(id).png") })
            let copyURL = textURL.deletingLastPathComponent().appendingPathComponent(relativePath)
            XCTAssertEqual(try Data(contentsOf: copyURL), original)
        }
    }

    func testPlainTextImageReferencesPreserveTextAndDistinctImagesAfterReopen() async throws {
        let text = "Text retained with images\n"
        let textID = try await storage.insert(type: .text, textContent: text, imageData: nil,
            sourceBundleId: "fixture.text", contentHash: "fixture.text", byteSize: text.utf8.count)
        let red = try makePNG(red: 255, blue: 0)
        let blue = try makePNG(red: 0, blue: 255)
        XCTAssertNotEqual(red, blue)
        let redID = try await insertImage(red, source: "fixture.red")
        let blueID = try await insertImage(blue, source: "fixture.blue")
        try await storage.setPinned(id: redID, pinned: true)
        let ids = [textID, redID, blueID]
        let beforeRows = try await storage.fetchForExport(ids: ids)
        let expected = [redID: red, blueID: blue]
        let earlier = try await service.export(scope: .selected(ids), format: .plainText,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("plain-first"))
        try assertPlainTextImages(earlier, expected: expected, itemCount: 3)
        let earlierBytes = try Data(contentsOf: earlier.files[0])
        XCTAssertTrue(try String(contentsOf: earlier.files[0], encoding: .utf8).contains(text))

        await storage.close()
        storage = StorageManager(baseDirectory: tempExportDir.appendingPathComponent("database", isDirectory: true))
        service = ExportService(storage: storage)
        try await storage.open()
        let reopenedRows = try await storage.fetchForExport(ids: ids)
        XCTAssertEqual(Set(reopenedRows.map(\.id)), Set(beforeRows.map(\.id)))
        for row in beforeRows {
            XCTAssertEqual(reopenedRows.first { $0.id == row.id }, row)
            if let path = row.imagePath {
                let sourceURL = await storage.imageURL(for: path)
                XCTAssertEqual(try Data(contentsOf: sourceURL), expected[row.id])
            }
        }
        let retry = try await service.export(scope: .selected(ids), format: .plainText,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("plain-reopened"))
        try assertPlainTextImages(retry, expected: expected, itemCount: 3)
        XCTAssertTrue(try String(contentsOf: retry.files[0], encoding: .utf8).contains(text))
        try assertPlainTextImages(earlier, expected: expected, itemCount: 3)
        XCTAssertEqual(try Data(contentsOf: earlier.files[0]), earlierBytes)
    }

    func testPlainTextMissingImageFailsAndRestoredSourceRetriesWithoutChangingEarlierExport() async throws {
        let png = try makePNG(red: 0, blue: 255)
        let id = try await insertImage(png, source: "fixture.plain-missing")
        let earlier = try await service.export(scope: .selected([id]), format: .plainText,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("plain-earlier"))
        let earlierBytes = try Data(contentsOf: earlier.files[0])
        let item = try await storage.fetchItem(id: id)
        let sourceURL = await storage.imageURL(for: try XCTUnwrap(item?.imagePath))
        try FileManager.default.removeItem(at: sourceURL)
        let failedDestination = tempExportDir.appendingPathComponent("plain-failed")
        do {
            _ = try await service.export(scope: .selected([id]), format: .plainText,
                includeImageRefs: true, destinationDir: failedDestination)
            XCTFail("Missing source image must fail the plain text export")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, NSFileReadNoSuchFileError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedDestination.appendingPathComponent("export.txt").path))
        let afterFailure = try await storage.fetchItem(id: id)
        XCTAssertEqual(afterFailure, item)
        try png.write(to: sourceURL, options: .atomic)
        let retry = try await service.export(scope: .selected([id]), format: .plainText,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("plain-restored"))
        try assertPlainTextImages(retry, expected: [id: png], itemCount: 1)
        try assertPlainTextImages(earlier, expected: [id: png], itemCount: 1)
        XCTAssertEqual(try Data(contentsOf: earlier.files[0]), earlierBytes)
        XCTAssertEqual(try Data(contentsOf: sourceURL), png)
    }

    func testPlainTextImageWithoutStoredPathFailsExplicitly() async throws {
        let id = try await insertImage(nil, source: "fixture.plain-no-path")
        let destination = tempExportDir.appendingPathComponent("plain-no-path")
        do {
            _ = try await service.export(scope: .selected([id]), format: .plainText,
                includeImageRefs: true, destinationDir: destination)
            XCTFail("An image row without its stored path must fail the plain text export")
        } catch ExportError.writeError(let message) {
            XCTAssertTrue(message.contains("\(id)"))
            XCTAssertTrue(message.contains("no stored image path"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("export.txt").path))
    }

    func testPlainTextWithoutImageReferencesKeepsPlaceholderWithoutCopying() async throws {
        let id = try await insertImage(nil, source: "fixture.plain-placeholder")
        let destination = tempExportDir.appendingPathComponent("plain-placeholder")
        let result = try await service.export(scope: .selected([id]), format: .plainText,
            includeImageRefs: false, destinationDir: destination)
        XCTAssertEqual(result.itemCount, 1)
        let text = try String(contentsOf: XCTUnwrap(result.files.first), encoding: .utf8)
        XCTAssertTrue(text.contains("[Image]\n"))
        XCTAssertTrue(try imageReferences(in: result.files[0]).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("images").path))
    }

    func testSameSecondImagesKeepDistinctBytesAndPixelsAfterReopenAndRetry() async throws {
        let red = try makePNG(red: 255, blue: 0)
        let blue = try makePNG(red: 0, blue: 255)
        XCTAssertNotEqual(red, blue)
        let redID = try await insertImage(red, source: "fixture.red")
        let blueID = try await insertImage(blue, source: "fixture.blue")
        // Pin both fixture rows to one second in the real SQLite store so the
        // regression is deterministic even if insertion straddles a clock tick.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempExportDir.appendingPathComponent("database/clipstash.db").path, &db), SQLITE_OK)
        guard let db else { return XCTFail("Fixture database did not open") }
        let status = sqlite3_exec(db, "UPDATE items SET createdAt = 1700000000", nil, nil, nil)
        sqlite3_close(db)
        XCTAssertEqual(status, SQLITE_OK)
        let rows = try await storage.fetchForExport(ids: [redID, blueID])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.createdAt)).count, 1)
        let destination = tempExportDir.appendingPathComponent("first-export")
        let result = try await service.export(scope: .selected([redID, blueID]), format: .markdown,
            includeImageRefs: true, destinationDir: destination)
        let expected = ["fixture.red": red, "fixture.blue": blue]
        try assertImages(result, expected: expected)
        let firstMarkdown = try Data(contentsOf: result.files[0])
        await storage.close()
        try await storage.open()
        let retry = try await service.export(scope: .selected([redID, blueID]), format: .markdown,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("retry-export"))
        try assertImages(retry, expected: expected)
        try assertImages(result, expected: expected)
        XCTAssertEqual(try Data(contentsOf: result.files[0]), firstMarkdown)
    }

    func testMissingImageThrowsAndRestoredSourceRetriesWithoutChangingEarlierExport() async throws {
        let png = try makePNG(red: 0, blue: 255)
        let id = try await insertImage(png, source: "fixture.missing")
        let earlier = try await service.export(scope: .selected([id]), format: .markdown,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("earlier-export"))
        let earlierMarkdown = try Data(contentsOf: earlier.files[0])
        let item = try await storage.fetchItem(id: id)
        let imagePath = try XCTUnwrap(item?.imagePath)
        let sourceURL = await storage.imageURL(for: imagePath)
        try FileManager.default.removeItem(at: sourceURL)
        let failedDestination = tempExportDir.appendingPathComponent("failed-export")
        do {
            _ = try await service.export(scope: .selected([id]), format: .markdown,
                includeImageRefs: true, destinationDir: failedDestination)
            XCTFail("Missing source image must fail the export")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, NSFileReadNoSuchFileError)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: failedDestination.appendingPathComponent("export.md").path))
        try png.write(to: sourceURL, options: .atomic)
        await storage.close()
        try await storage.open()
        let retry = try await service.export(scope: .selected([id]), format: .markdown,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("restored-export"))
        try assertImages(retry, expected: ["fixture.missing": png])
        try assertImages(earlier, expected: ["fixture.missing": png])
        XCTAssertEqual(try Data(contentsOf: earlier.files[0]), earlierMarkdown)
        XCTAssertEqual(try Data(contentsOf: sourceURL), png)
    }

    func testImageWithoutStoredPathFailsExplicitly() async throws {
        let id = try await insertImage(nil, source: "fixture.no-path")
        do {
            _ = try await service.export(scope: .selected([id]), format: .markdown,
                includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("no-path-export"))
            XCTFail("An image row without its stored path must fail the export")
        } catch ExportError.writeError(let message) {
            XCTAssertTrue(message.contains("\(id)"))
            XCTAssertTrue(message.contains("no stored image path"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConflictingImageFailsAndPreservesExistingFilesAndEarlierExport() async throws {
        let png = try makePNG(red: 255, blue: 0)
        let id = try await insertImage(png, source: "fixture.conflict")
        let earlier = try await service.export(scope: .selected([id]), format: .markdown,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("completed-export"))
        let earlierMarkdown = try Data(contentsOf: earlier.files[0])
        let relativeImage = try XCTUnwrap(imageReferences(in: earlier.files[0]).first)
        let destination = tempExportDir.appendingPathComponent("conflicting-export")
        let conflictURL = destination.appendingPathComponent(relativeImage)
        try FileManager.default.createDirectory(at: conflictURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sentinel = Data("Existing unrelated image bytes".utf8)
        try sentinel.write(to: conflictURL)
        let existingMarkdown = destination.appendingPathComponent("export.md")
        let sentinelMarkdown = Data("Existing unrelated Markdown".utf8)
        try sentinelMarkdown.write(to: existingMarkdown)
        let unrelated = destination.appendingPathComponent("notes.txt")
        try sentinel.write(to: unrelated)
        do {
            _ = try await service.export(scope: .selected([id]), format: .markdown,
                includeImageRefs: true, destinationDir: destination)
            XCTFail("An existing conflicting image must fail the export")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, NSFileWriteFileExistsError)
        }
        XCTAssertEqual(try Data(contentsOf: conflictURL), sentinel)
        XCTAssertEqual(try Data(contentsOf: existingMarkdown), sentinelMarkdown)
        XCTAssertEqual(try Data(contentsOf: unrelated), sentinel)
        XCTAssertEqual(try Data(contentsOf: earlier.files[0]), earlierMarkdown)
        try assertImages(earlier, expected: ["fixture.conflict": png])
        let retry = try await service.export(scope: .selected([id]), format: .markdown,
            includeImageRefs: true, destinationDir: tempExportDir.appendingPathComponent("conflict-retry"))
        try assertImages(retry, expected: ["fixture.conflict": png])
    }

}
