import Foundation

/// Represents a clipboard history item
struct ClipItem: Identifiable, Equatable, Hashable {
    let id: Int64
    let createdAt: Date
    let type: ClipItemType
    let textContent: String?
    let imagePath: String?
    let sourceBundleId: String?
    let contentHash: String
    var pinned: Bool
    var protected: Bool
    let byteSize: Int
    
    enum ClipItemType: String {
        case text
        case image
    }
    
    /// Preview text for display (truncated)
    var preview: String {
        switch type {
        case .text:
            let text = textContent ?? ""
            if text.count <= 100 {
                return text
            }
            return String(text.prefix(100)) + "..."
        case .image:
            return "[Image]"
        }
    }
    
    /// Formatted timestamp for display
    var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    /// Source app name (extracted from bundle ID)
    var sourceAppName: String? {
        guard let bundleId = sourceBundleId else { return nil }
        // Extract app name from bundle ID (last component, cleaned up)
        let components = bundleId.split(separator: ".")
        if let lastComponent = components.last {
            return String(lastComponent).capitalized
        }
        return bundleId
    }
}

// MARK: - Database Row Mapping

extension ClipItem {
    /// Create ClipItem from SQLite row data
    static func from(
        id: Int64,
        createdAt: Int64,
        type: String,
        textContent: String?,
        imagePath: String?,
        sourceBundleId: String?,
        contentHash: String,
        pinned: Int,
        protected: Int,
        byteSize: Int
    ) -> ClipItem {
        ClipItem(
            id: id,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAt)),
            type: ClipItemType(rawValue: type) ?? .text,
            textContent: textContent,
            imagePath: imagePath,
            sourceBundleId: sourceBundleId,
            contentHash: contentHash,
            pinned: pinned != 0,
            protected: protected != 0,
            byteSize: byteSize
        )
    }
}
