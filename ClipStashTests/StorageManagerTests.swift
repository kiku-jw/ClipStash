import XCTest
@testable import ClipStash

/// Unit tests for StorageManager following TDD
final class StorageManagerTests: XCTestCase {
    
    var storage: TestableStorageManager!
    
    override func setUp() async throws {
        storage = TestableStorageManager()
        try await storage.open()
    }
    
    override func tearDown() async throws {
        await storage.close()
        storage = nil
    }
    
    // MARK: - Task 2: Insert & Fetch
    
    func testInsertTextItem() async throws {
        // Arrange
        let text = "Hello, World!"
        let hash = "abc123"
        
        // Act
        let id = try await storage.insert(
            type: .text,
            textContent: text,
            imageData: nil,
            sourceBundleId: "com.test.app",
            contentHash: hash,
            byteSize: text.utf8.count
        )
        
        // Assert
        XCTAssertGreaterThan(id, 0, "Insert should return positive ID")
        
        let items = try await storage.fetchItems(limit: 10, offset: 0)
        XCTAssertEqual(items.count, 1, "Should have 1 item")
        XCTAssertEqual(items.first?.textContent, text)
        XCTAssertEqual(items.first?.contentHash, hash)
    }
    
    func testInsertMultipleItems() async throws {
        // Arrange & Act
        for i in 1...5 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 10
            )
        }
        
        // Assert
        let count = try await storage.count()
        XCTAssertEqual(count, 5, "Should have 5 items")
    }
    
    // MARK: - Task 4: Deduplication
    
    func testDeduplication() async throws {
        // Arrange
        let hash = "duplicate_hash"
        
        // Act
        _ = try await storage.insert(
            type: .text,
            textContent: "First",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: hash,
            byteSize: 5
        )
        
        let exists = try await storage.exists(contentHash: hash)
        
        // Assert
        XCTAssertTrue(exists, "Hash should exist after insert")
    }
    
    func testNonExistentHash() async throws {
        // Act
        let exists = try await storage.exists(contentHash: "non_existent")
        
        // Assert
        XCTAssertFalse(exists, "Non-existent hash should return false")
    }
    
    // MARK: - Task 5: Eviction
    
    func testEviction() async throws {
        // Arrange: Insert 10 items
        for i in 1...10 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 10
            )
            // Small delay to ensure different timestamps
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        // Act: Evict to limit 5
        try await storage.evict(limit: 5)
        
        // Assert
        let count = try await storage.count()
        XCTAssertEqual(count, 5, "Should have 5 items after eviction")
        
        // Verify oldest items were removed (items 1-5)
        let items = try await storage.fetchItems(limit: 10, offset: 0)
        for item in items {
            XCTAssertFalse(item.textContent?.contains("Item 1") ?? false, "Oldest items should be evicted")
        }
    }
    
    // MARK: - Task 6: Search
    
    func testSearch() async throws {
        // Arrange
        _ = try await storage.insert(
            type: .text,
            textContent: "Apple pie recipe",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "h1",
            byteSize: 20
        )
        _ = try await storage.insert(
            type: .text,
            textContent: "Banana smoothie",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "h2",
            byteSize: 20
        )
        _ = try await storage.insert(
            type: .text,
            textContent: "Apple cider",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "h3",
            byteSize: 20
        )
        
        // Act
        let results = try await storage.search(query: "Apple", limit: 10, offset: 0)
        
        // Assert
        XCTAssertEqual(results.count, 2, "Should find 2 items with 'Apple'")
        XCTAssertTrue(results.allSatisfy { $0.textContent?.contains("Apple") ?? false })
    }
    
    func testSearchNoResults() async throws {
        // Arrange
        _ = try await storage.insert(
            type: .text,
            textContent: "Hello World",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "h1",
            byteSize: 10
        )
        
        // Act
        let results = try await storage.search(query: "xyz123", limit: 10, offset: 0)
        
        // Assert
        XCTAssertEqual(results.count, 0, "Should find no items")
    }
    
    // MARK: - Task 7: Paging
    
    func testPaging() async throws {
        // Arrange: Insert 20 items
        for i in 1...20 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 10
            )
        }
        
        // Act: Fetch first page
        let page1 = try await storage.fetchItems(limit: 10, offset: 0)
        
        // Act: Fetch second page
        let page2 = try await storage.fetchItems(limit: 10, offset: 10)
        
        // Assert
        XCTAssertEqual(page1.count, 10, "First page should have 10 items")
        XCTAssertEqual(page2.count, 10, "Second page should have 10 items")
        
        // Verify no overlap
        let page1Ids = Set(page1.map { $0.id })
        let page2Ids = Set(page2.map { $0.id })
        XCTAssertTrue(page1Ids.isDisjoint(with: page2Ids), "Pages should not overlap")
    }
    
    func testPagingBeyondEnd() async throws {
        // Arrange: Insert 5 items
        for i in 1...5 {
            _ = try await storage.insert(
                type: .text,
                textContent: "Item \(i)",
                imageData: nil,
                sourceBundleId: nil,
                contentHash: "hash\(i)",
                byteSize: 10
            )
        }
        
        // Act: Fetch beyond available items
        let items = try await storage.fetchItems(limit: 10, offset: 100)
        
        // Assert
        XCTAssertEqual(items.count, 0, "Should return empty when offset exceeds count")
    }
    
    // MARK: - Task 10: Delete
    
    func testDelete() async throws {
        // Arrange
        let id = try await storage.insert(
            type: .text,
            textContent: "To delete",
            imageData: nil,
            sourceBundleId: nil,
            contentHash: "del1",
            byteSize: 10
        )
        
        // Act
        try await storage.delete(id: id)
        
        // Assert
        let count = try await storage.count()
        XCTAssertEqual(count, 0, "Should have 0 items after delete")
    }
}
