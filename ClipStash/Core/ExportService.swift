import Foundation
import AppKit

/// Service for exporting clipboard history to files
actor ExportService {
    static let shared = ExportService()
    
    /// Target chunk size in bytes (~180KB for NotebookLM compatibility)
    private let targetChunkBytes = 180_000
    
    // MARK: - Export Options
    
    enum ExportFormat {
        case markdown
        case plainText
        
        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .plainText: return "txt"
            }
        }
    }
    
    enum ExportScope {
        case lastN(Int)
        case today
        case lastWeek
        case pinnedOnly
        case selected([Int64])
    }
    
    struct ExportResult {
        let files: [URL]
        let itemCount: Int
        let totalBytes: Int
    }
    
    // MARK: - Export
    
    func export(
        scope: ExportScope,
        format: ExportFormat,
        includeImageRefs: Bool = false,
        destinationDir: URL? = nil
    ) async throws -> ExportResult {
        // Fetch items based on scope
        let items = try await fetchItems(for: scope)
        
        guard !items.isEmpty else {
            throw ExportError.noItemsToExport
        }
        
        // Determine destination directory
        let destDir = destinationDir ?? getDefaultExportDirectory()
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Generate content and split if needed
        let files = try await generateFiles(
            items: items,
            format: format,
            includeImageRefs: includeImageRefs,
            destinationDir: destDir
        )
        
        let totalBytes = files.reduce(0) { sum, url in
            sum + (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0) ?? 0
        }
        
        return ExportResult(
            files: files,
            itemCount: items.count,
            totalBytes: totalBytes
        )
    }
    
    // MARK: - Fetch Items
    
    private func fetchItems(for scope: ExportScope) async throws -> [ClipItem] {
        switch scope {
        case .lastN(let n):
            return try await StorageManager.shared.fetchForExport(lastN: n)
            
        case .today:
            let startOfDay = Calendar.current.startOfDay(for: Date())
            return try await StorageManager.shared.fetchForExport(since: startOfDay)
            
        case .lastWeek:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            return try await StorageManager.shared.fetchForExport(since: weekAgo)
            
        case .pinnedOnly:
            return try await StorageManager.shared.fetchForExport(pinnedOnly: true)
            
        case .selected(let ids):
            return try await StorageManager.shared.fetchForExport(ids: ids)
        }
    }
    
    // MARK: - Generate Files
    
    private func generateFiles(
        items: [ClipItem],
        format: ExportFormat,
        includeImageRefs: Bool,
        destinationDir: URL
    ) async throws -> [URL] {
        var files: [URL] = []
        var currentContent = ""
        var currentBytes = 0
        var partNumber = 1
        
        // Generate header
        let header = generateHeader(format: format)
        currentContent = header
        currentBytes = header.utf8.count
        
        // Copy images if needed
        var imageCopyDir: URL?
        if includeImageRefs {
            imageCopyDir = destinationDir.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: imageCopyDir!, withIntermediateDirectories: true)
        }
        
        for item in items {
            let entry = try await generateEntry(item, format: format, includeImageRefs: includeImageRefs, imageCopyDir: imageCopyDir)
            let entryBytes = entry.utf8.count
            
            // Check if we need to split
            if currentBytes + entryBytes > targetChunkBytes && currentBytes > header.utf8.count {
                // Write current file
                let file = try writeFile(currentContent, part: partNumber, format: format, destinationDir: destinationDir)
                files.append(file)
                
                partNumber += 1
                currentContent = header
                currentBytes = header.utf8.count
            }
            
            currentContent += entry
            currentBytes += entryBytes
        }
        
        // Write final file
        if currentBytes > header.utf8.count {
            let file = try writeFile(currentContent, part: files.isEmpty ? nil : partNumber, format: format, destinationDir: destinationDir)
            files.append(file)
        }
        
        return files
    }
    
    // MARK: - Content Generation
    
    private func generateHeader(format: ExportFormat) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = dateFormatter.string(from: Date())
        
        switch format {
        case .markdown:
            return "# Clipboard Export — \(timestamp)\n\n"
        case .plainText:
            return "Clipboard Export — \(timestamp)\n\n" + String(repeating: "=", count: 40) + "\n\n"
        }
    }
    
    private func generateEntry(_ item: ClipItem, format: ExportFormat, includeImageRefs: Bool, imageCopyDir: URL?) async throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: item.createdAt)
        
        let source = item.sourceBundleId ?? "unknown"
        
        switch format {
        case .markdown:
            return try await generateMarkdownEntry(item, timestamp: timestamp, source: source, includeImageRefs: includeImageRefs, imageCopyDir: imageCopyDir)
        case .plainText:
            return generatePlainTextEntry(item, timestamp: timestamp, source: source)
        }
    }
    
    private func generateMarkdownEntry(_ item: ClipItem, timestamp: String, source: String, includeImageRefs: Bool, imageCopyDir: URL?) async throws -> String {
        var entry = "## \(timestamp) (\(source))\n\n"
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                entry += "```text\n\(text)\n```\n\n"
            }
            
        case .image:
            if includeImageRefs, let imagePath = item.imagePath, let imageCopyDir = imageCopyDir {
                // Copy image to export directory
                let sourceURL = await StorageManager.shared.imageURL(for: imagePath)
                let destFilename = generateImageFilename(from: item.createdAt, originalPath: imagePath)
                let destURL = imageCopyDir.appendingPathComponent(destFilename)
                
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                
                entry += "[Image] images/\(destFilename)\n\n"
            } else {
                entry += "[Image]\n\n"
            }
        }
        
        return entry
    }
    
    private func generatePlainTextEntry(_ item: ClipItem, timestamp: String, source: String) -> String {
        var entry = "[\(timestamp)] (\(source))\n"
        
        switch item.type {
        case .text:
            if let text = item.textContent {
                entry += text + "\n"
            }
        case .image:
            entry += "[Image]\n"
        }
        
        entry += "\n" + String(repeating: "-", count: 40) + "\n\n"
        
        return entry
    }
    
    private func generateImageFilename(from date: Date, originalPath: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: date)
        
        let ext = (originalPath as NSString).pathExtension
        return "\(timestamp).\(ext.isEmpty ? "png" : ext)"
    }
    
    // MARK: - File Writing
    
    private func writeFile(_ content: String, part: Int?, format: ExportFormat, destinationDir: URL) throws -> URL {
        let baseName = part != nil ? "export_part\(String(format: "%02d", part!))" : "export"
        let filename = "\(baseName).\(format.fileExtension)"
        let fileURL = destinationDir.appendingPathComponent(filename)
        
        // Write atomically
        let tempURL = destinationDir.appendingPathComponent(UUID().uuidString + ".tmp")
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        
        // Move to final location
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        
        return fileURL
    }
    
    // MARK: - Helpers
    
    private func getDefaultExportDirectory() -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        return downloads.appendingPathComponent("ClipStash_Export_\(timestamp)", isDirectory: true)
    }
    
    // MARK: - Actions
    
    @MainActor
    func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
    
    @MainActor
    func openNotebookLM() {
        if let url = URL(string: "https://notebooklm.google.com") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Errors

enum ExportError: Error, LocalizedError {
    case noItemsToExport
    case writeError(String)
    
    var errorDescription: String? {
        switch self {
        case .noItemsToExport:
            return "No items to export"
        case .writeError(let msg):
            return "Failed to write export file: \(msg)"
        }
    }
}
