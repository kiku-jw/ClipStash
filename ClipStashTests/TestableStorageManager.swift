import Foundation
import SQLite3
import CryptoKit

/// Testable version of StorageManager that uses in-memory SQLite
actor TestableStorageManager {
    private var db: OpaquePointer?
    private var fts5Available = false
    
    private let imagesPath: URL
    
    init() {
        let tempDir = FileManager.default.temporaryDirectory
        imagesPath = tempDir.appendingPathComponent("ClipStashTests/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesPath, withIntermediateDirectories: true)
    }
    
    // MARK: - Database Lifecycle
    
    func open() throws {
        guard db == nil else { return }
        
        // Use in-memory database for testing
        if sqlite3_open(":memory:", &db) != SQLITE_OK {
            throw StorageError.cannotOpenDatabase(errorMessage)
        }
        
        // Check FTS5 support
        fts5Available = checkFTS5Support()
        
        // Create schema
        try createSchema()
    }
    
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    private func createSchema() throws {
        try execute("""
            CREATE TABLE IF NOT EXISTS items (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                createdAt INTEGER NOT NULL,
                type TEXT NOT NULL,
                textContent TEXT,
                imagePath TEXT,
                sourceBundleId TEXT,
                contentHash TEXT NOT NULL,
                pinned INTEGER DEFAULT 0,
                protected INTEGER DEFAULT 0,
                byteSize INTEGER NOT NULL
            )
        """)
        
        try execute("CREATE INDEX IF NOT EXISTS idx_items_createdAt ON items(createdAt DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_contentHash ON items(contentHash)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_pinned ON items(pinned)")
        
        if fts5Available {
            try execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                    textContent,
                    content='items',
                    content_rowid='id'
                )
            """)
            
            try execute("""
                CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, textContent) VALUES (new.id, new.textContent);
                END
            """)
            
            try execute("""
                CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, textContent) VALUES('delete', old.id, old.textContent);
                END
            """)
        }
    }
    
    private func checkFTS5Support() -> Bool {
        do {
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS _fts5_test USING fts5(c)")
            try execute("DROP TABLE IF EXISTS _fts5_test")
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - CRUD Operations
    
    func insert(
        type: ClipItem.ClipItemType,
        textContent: String?,
        imageData: Data?,
        sourceBundleId: String?,
        contentHash: String,
        byteSize: Int
    ) throws -> Int64 {
        var imagePath: String?
        if let imageData = imageData, type == .image {
            let filename = "\(UUID().uuidString).png"
            let fileURL = imagesPath.appendingPathComponent(filename)
            try imageData.write(to: fileURL, options: .atomic)
            imagePath = filename
        }
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = """
            INSERT INTO items (createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize)
            VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?)
        """
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        let timestamp = Int64(Date().timeIntervalSince1970)
        sqlite3_bind_int64(stmt, 1, timestamp)
        sqlite3_bind_text(stmt, 2, type.rawValue, -1, SQLITE_TRANSIENT)
        
        if let text = textContent {
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        
        if let path = imagePath {
            sqlite3_bind_text(stmt, 4, path, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        
        if let bundleId = sourceBundleId {
            sqlite3_bind_text(stmt, 5, bundleId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        
        sqlite3_bind_text(stmt, 6, contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 7, Int32(byteSize))
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StorageError.insertFailed(errorMessage)
        }
        
        return sqlite3_last_insert_rowid(db)
    }
    
    func exists(contentHash: String) throws -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = "SELECT 1 FROM items WHERE contentHash = ? LIMIT 1"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        sqlite3_bind_text(stmt, 1, contentHash, -1, SQLITE_TRANSIENT)
        
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    
    func fetchItems(limit: Int, offset: Int) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = "SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize FROM items ORDER BY pinned DESC, createdAt DESC LIMIT ? OFFSET ?"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))
        
        return try fetchRows(stmt)
    }
    
    func search(query: String, limit: Int, offset: Int) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql: String
        if fts5Available {
            sql = """
                SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize
                FROM items
                WHERE id IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)
                ORDER BY pinned DESC, createdAt DESC
                LIMIT ? OFFSET ?
            """
        } else {
            sql = """
                SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize
                FROM items
                WHERE textContent LIKE '%' || ? || '%'
                ORDER BY pinned DESC, createdAt DESC
                LIMIT ? OFFSET ?
            """
        }
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        let searchTerm = fts5Available ? "\"\(query)\"" : query
        sqlite3_bind_text(stmt, 1, searchTerm, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_bind_int(stmt, 3, Int32(offset))
        
        return try fetchRows(stmt)
    }
    
    func delete(id: Int64) throws {
        try execute("DELETE FROM items WHERE id = \(id)")
    }
    
    func count() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items", -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    func countUnpinned() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items WHERE pinned = 0", -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }
    
    func evict(limit: Int) throws {
        let unpinnedCount = try countUnpinned()
        
        if unpinnedCount > limit {
            let toDelete = unpinnedCount - limit
            try execute("DELETE FROM items WHERE pinned = 0 ORDER BY createdAt ASC LIMIT \(toDelete)")
        }
    }
    
    var isFTS5Available: Bool {
        fts5Available
    }
    
    // MARK: - Helpers
    
    private func execute(_ sql: String) throws {
        var errorPtr: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorPtr) != SQLITE_OK {
            let message = errorPtr.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorPtr)
            throw StorageError.executeFailed(message)
        }
    }
    
    private func fetchRows(_ stmt: OpaquePointer?) throws -> [ClipItem] {
        var items: [ClipItem] = []
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let createdAt = sqlite3_column_int64(stmt, 1)
            let type = String(cString: sqlite3_column_text(stmt, 2))
            
            let textContent: String?
            if let text = sqlite3_column_text(stmt, 3) {
                textContent = String(cString: text)
            } else {
                textContent = nil
            }
            
            let imagePath: String?
            if let path = sqlite3_column_text(stmt, 4) {
                imagePath = String(cString: path)
            } else {
                imagePath = nil
            }
            
            let sourceBundleId: String?
            if let bundleId = sqlite3_column_text(stmt, 5) {
                sourceBundleId = String(cString: bundleId)
            } else {
                sourceBundleId = nil
            }
            
            let contentHash = String(cString: sqlite3_column_text(stmt, 6))
            let pinned = sqlite3_column_int(stmt, 7)
            let protected = sqlite3_column_int(stmt, 8)
            let byteSize = sqlite3_column_int(stmt, 9)
            
            let item = ClipItem.from(
                id: id,
                createdAt: createdAt,
                type: type,
                textContent: textContent,
                imagePath: imagePath,
                sourceBundleId: sourceBundleId,
                contentHash: contentHash,
                pinned: Int(pinned),
                protected: Int(protected),
                byteSize: Int(byteSize)
            )
            
            items.append(item)
        }
        
        return items
    }
    
    private var errorMessage: String {
        if let error = sqlite3_errmsg(db) {
            return String(cString: error)
        }
        return "Unknown SQLite error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
