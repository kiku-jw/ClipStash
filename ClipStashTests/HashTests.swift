import XCTest
@testable import ClipStash
import CryptoKit

/// Unit tests for hash computation
final class HashTests: XCTestCase {
    
    // MARK: - Task 10: Hash Computation
    
    func testHashComputationConsistency() {
        // Arrange
        let text = "Hello, World!"
        let data = Data(text.utf8)
        
        // Act
        let hash1 = computeHash(type: "text", data: data)
        let hash2 = computeHash(type: "text", data: data)
        
        // Assert
        XCTAssertEqual(hash1, hash2, "Same input should produce same hash")
    }
    
    func testHashDifferentTypes() {
        // Arrange
        let data = Data("content".utf8)
        
        // Act
        let textHash = computeHash(type: "text", data: data)
        let imageHash = computeHash(type: "image", data: data)
        
        // Assert
        XCTAssertNotEqual(textHash, imageHash, "Different types should produce different hashes")
    }
    
    func testHashDifferentContent() {
        // Arrange
        let data1 = Data("Hello".utf8)
        let data2 = Data("World".utf8)
        
        // Act
        let hash1 = computeHash(type: "text", data: data1)
        let hash2 = computeHash(type: "text", data: data2)
        
        // Assert
        XCTAssertNotEqual(hash1, hash2, "Different content should produce different hashes")
    }
    
    func testHashFormat() {
        // Arrange
        let data = Data("test".utf8)
        
        // Act
        let hash = computeHash(type: "text", data: data)
        
        // Assert
        XCTAssertEqual(hash.count, 64, "SHA256 hex should be 64 characters")
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Hash should be hex string")
    }
    
    // Helper matching ClipboardMonitor implementation
    private func computeHash(type: String, data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(type.utf8))
        hasher.update(data: data)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
