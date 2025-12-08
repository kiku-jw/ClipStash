import XCTest
@testable import ClipStash

final class ExportServiceTests: XCTestCase {
    
    var tempExportDir: URL!
    
    override func setUp() async throws {
        tempExportDir = FileManager.default.temporaryDirectory.appendingPathComponent("ClipStashExportTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempExportDir, withIntermediateDirectories: true)
        
        // Ensure storage is open
        try await StorageManager.shared.open()
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempExportDir)
    }
    
    // MARK: - Tests
    
    func testMarkdownExport() async throws {
        // Clear and insert test data
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Test export content",
            imageData: nil,
            sourceBundleId: "com.test.app",
            contentHash: "exporthash1",
            byteSize: 19
        )
        
        let result = try await ExportService.shared.export(
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
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Plain text export",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "plaintexthash",
            byteSize: 17
        )
        
        let result = try await ExportService.shared.export(
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
    
    func testAutoSplit() async throws {
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        // Insert items with large content to trigger splitting
        // Target is ~180KB, so insert enough to exceed that
        let largeText = String(repeating: "A", count: 50_000) // 50KB per item
        
        for i in 0..<5 {
            _ = try await StorageManager.shared.insert(
                type: .text,
                textContent: "\(largeText) Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "largehash\(i)",
                byteSize: 50_006
            )
        }
        
        let result = try await ExportService.shared.export(
            scope: .lastN(100),
            format: .markdown,
            includeImageRefs: false,
            destinationDir: tempExportDir
        )
        
        // Should have created multiple files due to auto-split
        XCTAssertGreaterThan(result.files.count, 1)
        
        // All files should be under ~200KB
        for file in result.files {
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            let size = attrs[.size] as? Int ?? 0
            XCTAssertLessThan(size, 250_000) // Allow some margin
        }
    }
    
    func testPinnedOnlyExport() async throws {
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        // Insert regular item
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Not pinned",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "notpinned",
            byteSize: 10
        )
        
        // Insert and pin item
        let pinnedId = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Pinned item",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "pinnedhash",
            byteSize: 11
        )
        try await StorageManager.shared.setPinned(id: pinnedId, pinned: true)
        
        let result = try await ExportService.shared.export(
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
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        do {
            _ = try await ExportService.shared.export(
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
}
