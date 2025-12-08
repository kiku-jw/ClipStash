import XCTest
@testable import ClipStash

final class StorageManagerTests: XCTestCase {
    
    var tempDBPath: URL!
    
    override func setUp() async throws {
        // Use a temporary database for testing
        tempDBPath = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDBPath, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDBPath)
    }
    
    // MARK: - Tests
    
    func testOpenDatabase() async throws {
        try await StorageManager.shared.open()
        // Should not throw
    }
    
    func testInsertAndFetch() async throws {
        try await StorageManager.shared.open()
        
        let id = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Hello, World!",
            imageData: nil,
            sourceBundleId: "com.apple.Safari",
            contentHash: "testhash123",
            byteSize: 13
        )
        
        XCTAssertGreaterThan(id, 0)
        
        let items = try await StorageManager.shared.fetchItems(limit: 10, offset: 0)
        XCTAssertFalse(items.isEmpty)
        
        let item = items.first { $0.id == id }
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.textContent, "Hello, World!")
        XCTAssertEqual(item?.sourceBundleId, "com.apple.Safari")
    }
    
    func testDeduplication() async throws {
        try await StorageManager.shared.open()
        
        let hash = "uniquehash456"
        
        // First insert
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Duplicate content",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: hash,
            byteSize: 17
        )
        
        // Check exists
        let exists = try await StorageManager.shared.exists(contentHash: hash)
        XCTAssertTrue(exists)
        
        // Non-existent hash
        let notExists = try await StorageManager.shared.exists(contentHash: "nonexistent")
        XCTAssertFalse(notExists)
    }
    
    func testEviction() async throws {
        try await StorageManager.shared.open()
        
        // Clear existing data
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        // Insert 10 items
        for i in 0..<10 {
            _ = try await StorageManager.shared.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 6
            )
        }
        
        let countBefore = try await StorageManager.shared.count()
        XCTAssertEqual(countBefore, 10)
        
        // Evict to limit 5
        try await StorageManager.shared.evict(limit: 5)
        
        let countAfter = try await StorageManager.shared.countUnpinned()
        XCTAssertEqual(countAfter, 5)
    }
    
    func testPinned() async throws {
        try await StorageManager.shared.open()
        
        let id = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Pin me",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "pinhash",
            byteSize: 6
        )
        
        // Toggle pinned
        try await StorageManager.shared.togglePinned(id: id)
        
        let item = try await StorageManager.shared.fetchItem(id: id)
        XCTAssertTrue(item?.pinned ?? false)
        
        // Toggle again
        try await StorageManager.shared.togglePinned(id: id)
        
        let item2 = try await StorageManager.shared.fetchItem(id: id)
        XCTAssertFalse(item2?.pinned ?? true)
    }
    
    func testSearch() async throws {
        try await StorageManager.shared.open()
        
        // Clear and insert test data
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "The quick brown fox",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "searchhash1",
            byteSize: 19
        )
        
        _ = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Lazy dog sleeps",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "searchhash2",
            byteSize: 15
        )
        
        // Search for "fox"
        let results = try await StorageManager.shared.search(query: "fox", limit: 10, offset: 0)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.textContent, "The quick brown fox")
        
        // Search for "dog"
        let results2 = try await StorageManager.shared.search(query: "dog", limit: 10, offset: 0)
        XCTAssertEqual(results2.count, 1)
        XCTAssertEqual(results2.first?.textContent, "Lazy dog sleeps")
    }
    
    func testPaging() async throws {
        try await StorageManager.shared.open()
        
        // Clear existing data
        try await StorageManager.shared.clearAll(keepPinned: false)
        
        // Insert 20 items
        for i in 0..<20 {
            _ = try await StorageManager.shared.insert(
                type: .text,
                textContent: "Page item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "pagehash\(i)",
                byteSize: 12
            )
        }
        
        // Fetch first page
        let page1 = try await StorageManager.shared.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(page1.count, 10)
        
        // Fetch second page
        let page2 = try await StorageManager.shared.fetchItems(limit: 10, offset: 10)
        XCTAssertEqual(page2.count, 10)
        
        // Ensure no overlap
        let page1Ids = Set(page1.map { $0.id })
        let page2Ids = Set(page2.map { $0.id })
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids))
    }
    
    func testDelete() async throws {
        try await StorageManager.shared.open()
        
        let id = try await StorageManager.shared.insert(
            type: .text,
            textContent: "Delete me",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "deletehash",
            byteSize: 9
        )
        
        // Verify exists
        let item = try await StorageManager.shared.fetchItem(id: id)
        XCTAssertNotNil(item)
        
        // Delete
        try await StorageManager.shared.delete(id: id)
        
        // Verify deleted
        let deleted = try await StorageManager.shared.fetchItem(id: id)
        XCTAssertNil(deleted)
    }
}
