import Foundation
import CryptoKit
import Security

/// Helper for Keychain storage and optional AES-GCM encryption
enum KeychainHelper {
    
    private static let serviceName = "dev.kikuai.ClipStash"
    private static let encryptionKeyAccount = "EncryptionKey"
    
    // MARK: - Encryption Key Management
    
    /// Get or create the encryption key for protected items
    static func getOrCreateEncryptionKey() throws -> SymmetricKey {
        // Try to load existing key
        if let existingKey = try? loadEncryptionKey() {
            return existingKey
        }
        
        // Generate new key
        let newKey = SymmetricKey(size: .bits256)
        try saveEncryptionKey(newKey)
        return newKey
    }
    
    private static func loadEncryptionKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.loadFailed(status)
        }
        
        return SymmetricKey(data: data)
    }
    
    private static func saveEncryptionKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: encryptionKeyAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing if present
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Delete the encryption key (for testing or reset)
    static func deleteEncryptionKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: encryptionKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
    
    // MARK: - AES-GCM Encryption
    
    /// Encrypt data using AES-GCM
    static func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealFailed
        }
        
        return combined
    }
    
    /// Decrypt data using AES-GCM
    static func decrypt(_ encryptedData: Data) throws -> Data {
        let key = try getOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    /// Encrypt string to base64
    static func encryptString(_ string: String) throws -> String {
        let data = Data(string.utf8)
        let encrypted = try encrypt(data)
        return encrypted.base64EncodedString()
    }
    
    /// Decrypt base64 string
    static func decryptString(_ base64String: String) throws -> String {
        guard let data = Data(base64Encoded: base64String) else {
            throw EncryptionError.invalidBase64
        }
        let decrypted = try decrypt(data)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw EncryptionError.invalidUTF8
        }
        return string
    }
}

// MARK: - Errors

enum KeychainError: Error, LocalizedError {
    case loadFailed(OSStatus)
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let status):
            return "Failed to load from Keychain: \(status)"
        case .saveFailed(let status):
            return "Failed to save to Keychain: \(status)"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain: \(status)"
        }
    }
}

enum EncryptionError: Error, LocalizedError {
    case sealFailed
    case invalidBase64
    case invalidUTF8
    
    var errorDescription: String? {
        switch self {
        case .sealFailed:
            return "Failed to seal data"
        case .invalidBase64:
            return "Invalid base64 encoded data"
        case .invalidUTF8:
            return "Invalid UTF8 string"
        }
    }
}
