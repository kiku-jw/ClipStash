import Foundation
import SQLite3
import CryptoKit

/// SQLite-based storage manager with FTS5 search support
actor StorageManager {
    static let shared = StorageManager()
    
    private var db: OpaquePointer?
    private var fts5Available = false
    
    private let dbPath: URL
    private let imagesPath: URL
    
    // MARK: - Schema Version
    
    private let currentSchemaVersion = 1
    
    // MARK: - Initialization
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClipStash", isDirectory: true)
        
        // Create directories if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        
        dbPath = appDir.appendingPathComponent("clipstash.db")
        imagesPath = appDir.appendingPathComponent("images", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: imagesPath, withIntermediateDirectories: true)
    }
    
    // MARK: - Database Lifecycle
    
    func open() throws {
        guard db == nil else { return }
        
        if sqlite3_open(dbPath.path, &db) != SQLITE_OK {
            throw StorageError.cannotOpenDatabase(errorMessage)
        }
        
        // Enable WAL mode for better performance
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA synchronous = NORMAL")
        
        // Check FTS5 support
        fts5Available = checkFTS5Support()
        
        // Run migrations
        try migrate()
    }
    
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    // MARK: - Migrations
    
    private func migrate() throws {
        let version = try getSchemaVersion()
        
        if version < 1 {
            try createInitialSchema()
            try setSchemaVersion(1)
        }
        
        // Future migrations go here:
        // if version < 2 { ... }
    }
    
    private func getSchemaVersion() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int(stmt, 0))
            }
        }
        return 0
    }
    
    private func setSchemaVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }
    
    private func createInitialSchema() throws {
        // Main items table
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
        
        // Indexes
        try execute("CREATE INDEX IF NOT EXISTS idx_items_createdAt ON items(createdAt DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_contentHash ON items(contentHash)")
        try execute("CREATE INDEX IF NOT EXISTS idx_items_pinned ON items(pinned)")
        
        // FTS5 if available
        if fts5Available {
            try execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
                    textContent,
                    content='items',
                    content_rowid='id'
                )
            """)
            
            // Triggers to keep FTS in sync
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
            
            try execute("""
                CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, textContent) VALUES('delete', old.id, old.textContent);
                    INSERT INTO items_fts(rowid, textContent) VALUES (new.id, new.textContent);
                END
            """)
        }
    }
    
    // MARK: - FTS5 Detection
    
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
    
    /// Insert a new clipboard item
    func insert(
        type: ClipItem.ClipItemType,
        textContent: String?,
        imageData: Data?,
        sourceBundleId: String?,
        contentHash: String,
        byteSize: Int
    ) throws -> Int64 {
        // Handle image storage
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
    
    /// Check if content hash already exists
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
    
    /// Fetch items with paging
    func fetchItems(limit: Int, offset: Int, pinnedFirst: Bool = true) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let orderBy = pinnedFirst ? "pinned DESC, createdAt DESC" : "createdAt DESC"
        let sql = "SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize FROM items ORDER BY \(orderBy) LIMIT ? OFFSET ?"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))
        
        return try fetchRows(stmt)
    }
    
    /// Search items using FTS5 or LIKE fallback
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
        
        // For FTS5, wrap in quotes for phrase matching
        let searchTerm = fts5Available ? "\"\(query)\"" : query
        sqlite3_bind_text(stmt, 1, searchTerm, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))
        sqlite3_bind_int(stmt, 3, Int32(offset))
        
        return try fetchRows(stmt)
    }
    
    /// Delete an item by ID
    func delete(id: Int64) throws {
        // First get the image path if any
        let item = try fetchItem(id: id)

        // Delete from database using prepared statement
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "DELETE FROM items WHERE id = ?"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        sqlite3_bind_int64(stmt, 1, id)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StorageError.executeFailed(errorMessage)
        }

        // Delete image file if exists
        if let imagePath = item?.imagePath {
            let fileURL = imagesPath.appendingPathComponent(imagePath)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Toggle pinned status
    func togglePinned(id: Int64) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "UPDATE items SET pinned = NOT pinned WHERE id = ?"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        sqlite3_bind_int64(stmt, 1, id)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StorageError.executeFailed(errorMessage)
        }
    }

    /// Set pinned status
    func setPinned(id: Int64, pinned: Bool) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        let sql = "UPDATE items SET pinned = ? WHERE id = ?"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, id)

        if sqlite3_step(stmt) != SQLITE_DONE {
            throw StorageError.executeFailed(errorMessage)
        }
    }
    
    /// Fetch single item by ID
    func fetchItem(id: Int64) throws -> ClipItem? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = "SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize FROM items WHERE id = ?"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        sqlite3_bind_int64(stmt, 1, id)
        
        let items = try fetchRows(stmt)
        return items.first
    }
    
    /// Get total item count
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
    
    /// Get count of non-pinned items
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
    
    // MARK: - Eviction
    
    /// Remove oldest non-pinned items if over limit
    func evict(limit: Int) throws {
        let unpinnedCount = try countUnpinned()
        
        if unpinnedCount > limit {
            let toDelete = unpinnedCount - limit
            
            // Get image paths of items to delete
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            
            let sql = "SELECT id, imagePath FROM items WHERE pinned = 0 ORDER BY createdAt ASC LIMIT ?"
            
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
                throw StorageError.prepareFailed(errorMessage)
            }
            
            sqlite3_bind_int(stmt, 1, Int32(toDelete))
            
            var imagePaths: [String] = []
            var ids: [Int64] = []
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                ids.append(sqlite3_column_int64(stmt, 0))
                if let path = sqlite3_column_text(stmt, 1) {
                    imagePaths.append(String(cString: path))
                }
            }
            
            // Delete items using prepared statement
            if !ids.isEmpty {
                let placeholders = ids.map { _ in "?" }.joined(separator: ",")
                let deleteSql = "DELETE FROM items WHERE id IN (\(placeholders))"

                var deleteStmt: OpaquePointer?
                defer { sqlite3_finalize(deleteStmt) }

                if sqlite3_prepare_v2(db, deleteSql, -1, &deleteStmt, nil) != SQLITE_OK {
                    throw StorageError.prepareFailed(errorMessage)
                }

                for (index, id) in ids.enumerated() {
                    sqlite3_bind_int64(deleteStmt, Int32(index + 1), id)
                }

                if sqlite3_step(deleteStmt) != SQLITE_DONE {
                    throw StorageError.executeFailed(errorMessage)
                }

                // Delete image files
                for path in imagePaths {
                    let fileURL = imagesPath.appendingPathComponent(path)
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Clear all history (keeps pinned if specified)
    func clearAll(keepPinned: Bool = true) throws {
        // Get image paths to delete
        let sql = keepPinned ? "SELECT imagePath FROM items WHERE pinned = 0 AND imagePath IS NOT NULL" : "SELECT imagePath FROM items WHERE imagePath IS NOT NULL"
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        var imagePaths: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let path = sqlite3_column_text(stmt, 0) {
                imagePaths.append(String(cString: path))
            }
        }
        
        // Delete from database
        if keepPinned {
            try execute("DELETE FROM items WHERE pinned = 0")
        } else {
            try execute("DELETE FROM items")
        }
        
        // Delete image files
        for path in imagePaths {
            let fileURL = imagesPath.appendingPathComponent(path)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Export Helpers
    
    /// Fetch items for export with various filters
    func fetchForExport(
        lastN: Int? = nil,
        since: Date? = nil,
        pinnedOnly: Bool = false,
        ids: [Int64]? = nil
    ) throws -> [ClipItem] {
        var conditions: [String] = []
        var params: [Any] = []
        
        if pinnedOnly {
            conditions.append("pinned = 1")
        }
        
        if let since = since {
            conditions.append("createdAt >= ?")
            params.append(Int64(since.timeIntervalSince1970))
        }
        
        if let ids = ids, !ids.isEmpty {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            conditions.append("id IN (\(placeholders))")
            params.append(contentsOf: ids)
        }
        
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let limitClause = lastN.map { "LIMIT \($0)" } ?? ""
        
        let sql = """
            SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize
            FROM items
            \(whereClause)
            ORDER BY createdAt DESC
            \(limitClause)
        """
        
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        // Bind parameters
        var paramIndex: Int32 = 1
        for param in params {
            if let intValue = param as? Int64 {
                sqlite3_bind_int64(stmt, paramIndex, intValue)
            }
            paramIndex += 1
        }
        
        return try fetchRows(stmt)
    }
    
    /// Fetch items from specific apps for export
    func fetchForExport(bundleIds: [String]) throws -> [ClipItem] {
        guard !bundleIds.isEmpty else { return [] }

        let placeholders = bundleIds.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT id, createdAt, type, textContent, imagePath, sourceBundleId, contentHash, pinned, protected, byteSize
            FROM items
            WHERE sourceBundleId IN (\(placeholders))
            ORDER BY createdAt DESC
            """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }

        // Bind bundle IDs
        for (index, bundleId) in bundleIds.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), bundleId, -1, SQLITE_TRANSIENT)
        }

        return try fetchRows(stmt)
    }
    
    // MARK: - Diagnostics
    
    func getDatabaseSize() -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: dbPath.path)[.size] as? Int64) ?? 0
    }
    
    func getImagesFolderSize() -> Int64 {
        let enumerator = FileManager.default.enumerator(at: imagesPath, includingPropertiesForKeys: [.fileSizeKey])
        var totalSize: Int64 = 0
        
        while let url = enumerator?.nextObject() as? URL {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        
        return totalSize
    }
    
    /// Get unique source bundle IDs for filtering
    func getUniqueApps() throws -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        
        let sql = "SELECT DISTINCT sourceBundleId FROM items WHERE sourceBundleId IS NOT NULL ORDER BY sourceBundleId"
        
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw StorageError.prepareFailed(errorMessage)
        }
        
        var apps: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let bundleId = sqlite3_column_text(stmt, 0) {
                apps.append(String(cString: bundleId))
            }
        }
        return apps
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
    
    /// Get full path to image file
    func imageURL(for imagePath: String) -> URL {
        imagesPath.appendingPathComponent(imagePath)
    }
}

// MARK: - Errors

enum StorageError: Error, LocalizedError {
    case cannotOpenDatabase(String)
    case prepareFailed(String)
    case insertFailed(String)
    case executeFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .cannotOpenDatabase(let msg): return "Cannot open database: \(msg)"
        case .prepareFailed(let msg): return "SQL prepare failed: \(msg)"
        case .insertFailed(let msg): return "Insert failed: \(msg)"
        case .executeFailed(let msg): return "Execute failed: \(msg)"
        }
    }
}

// MARK: - SQLite Helpers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
