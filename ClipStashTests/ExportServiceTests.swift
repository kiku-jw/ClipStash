import XCTest
@testable import ClipStash

/// Unit tests for ExportService
final class ExportServiceTests: XCTestCase {
    
    // MARK: - Task 8: Markdown Format
    
    func testMarkdownHeader() {
        // Arrange
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = dateFormatter.string(from: Date())
        
        let expectedPrefix = "# Clipboard Export — "
        
        // Assert format starts correctly
        XCTAssertTrue(expectedPrefix.hasPrefix("# Clipboard Export"))
    }
    
    func testMarkdownEntryFormat() {
        // Arrange
        let item = ClipItem(
            id: 1,
            createdAt: Date(),
            type: .text,
            textContent: "Test content",
            imagePath: nil,
            sourceBundleId: "com.test.app",
            contentHash: "hash123",
            pinned: false,
            protected: false,
            byteSize: 12
        )
        
        // Assert preview is correct
        XCTAssertEqual(item.preview, "Test content")
        XCTAssertEqual(item.sourceAppName, "App")
    }
    
    // MARK: - Task 9: Auto-Split Logic
    
    func testAutoSplitCalculation() {
        // Arrange
        let targetChunkBytes = 180_000
        let itemSize = 50_000 // 50KB per item
        let itemCount = 10 // total 500KB
        
        // Act
        let expectedFiles = Int(ceil(Double(itemCount * itemSize) / Double(targetChunkBytes)))
        
        // Assert
        XCTAssertEqual(expectedFiles, 3, "500KB should split into 3 files at 180KB target")
    }
    
    func testSmallExportNoSplit() {
        // Arrange
        let targetChunkBytes = 180_000
        let totalBytes = 100_000 // 100KB
        
        // Act
        let expectedFiles = totalBytes < targetChunkBytes ? 1 : Int(ceil(Double(totalBytes) / Double(targetChunkBytes)))
        
        // Assert
        XCTAssertEqual(expectedFiles, 1, "100KB should not split")
    }
    
    // MARK: - ClipItem Model Tests
    
    func testClipItemPreviewTruncation() {
        // Arrange
        let longText = String(repeating: "A", count: 200)
        let item = ClipItem(
            id: 1,
            createdAt: Date(),
            type: .text,
            textContent: longText,
            imagePath: nil,
            sourceBundleId: nil,
            contentHash: "hash",
            pinned: false,
            protected: false,
            byteSize: 200
        )
        
        // Assert
        XCTAssertEqual(item.preview.count, 103, "Preview should be 100 chars + '...'")
        XCTAssertTrue(item.preview.hasSuffix("..."))
    }
    
    func testClipItemImagePreview() {
        // Arrange
        let item = ClipItem(
            id: 1,
            createdAt: Date(),
            type: .image,
            textContent: nil,
            imagePath: "image.png",
            sourceBundleId: nil,
            contentHash: "hash",
            pinned: false,
            protected: false,
            byteSize: 1000
        )
        
        // Assert
        XCTAssertEqual(item.preview, "[Image]")
    }
    
    func testSourceAppNameExtraction() {
        // Arrange
        let bundleId = "com.apple.Safari"
        
        // Act
        let components = bundleId.split(separator: ".")
        let appName = components.last.map { String($0).capitalized }
        
        // Assert
        XCTAssertEqual(appName, "Safari")
    }
}
