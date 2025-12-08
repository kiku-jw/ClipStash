import SwiftUI
import AppKit

/// Row view for a single clipboard item with image thumbnail support
struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    @State private var isHovered = false
    @State private var thumbnail: NSImage?
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Pin indicator or content preview
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 40, height: 40)
            } else if item.type == .image {
                // Image thumbnail
                thumbnailView
                    .frame(width: 40, height: 40)
                    .cornerRadius(4)
                    .clipped()
            } else {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .frame(width: 40, height: 40)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Content preview
                if item.type == .text {
                    Text(item.preview)
                        .font(.system(.body))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text("Image")
                        .font(.system(.body))
                        .foregroundColor(.primary)
                    
                    if let size = formatByteSize(item.byteSize) {
                        Text(size)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Metadata
                HStack(spacing: 4) {
                    if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    
                    Text(item.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Action buttons (visible on hover)
            if isHovered || isSelected {
                HStack(spacing: 4) {
                    Button(action: onTogglePin) {
                        Image(systemName: item.pinned ? "pin.slash" : "pin")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(item.pinned ? "Unpin" : "Pin")
                    
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.secondary.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .task {
            await loadThumbnail()
        }
    }
    
    // MARK: - Thumbnail View
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
        }
    }
    
    // MARK: - Helpers
    
    private func loadThumbnail() async {
        guard item.type == .image, let imagePath = item.imagePath else { return }
        
        let url = await StorageManager.shared.imageURL(for: imagePath)
        
        // Load and resize on background thread
        let loadedThumbnail = await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: url) else { return nil as NSImage? }
            
            // Create thumbnail (80x80 for retina)
            let thumbnailSize = NSSize(width: 80, height: 80)
            let thumbnail = NSImage(size: thumbnailSize)
            
            thumbnail.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            
            let aspectRatio = image.size.width / image.size.height
            var drawRect: NSRect
            
            if aspectRatio > 1 {
                // Wider than tall
                let height = thumbnailSize.height
                let width = height * aspectRatio
                let x = (thumbnailSize.width - width) / 2
                drawRect = NSRect(x: x, y: 0, width: width, height: height)
            } else {
                // Taller than wide
                let width = thumbnailSize.width
                let height = width / aspectRatio
                let y = (thumbnailSize.height - height) / 2
                drawRect = NSRect(x: 0, y: y, width: width, height: height)
            }
            
            image.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
            thumbnail.unlockFocus()
            
            return thumbnail
        }.value
        
        await MainActor.run {
            self.thumbnail = loadedThumbnail
        }
    }
    
    private func formatByteSize(_ bytes: Int) -> String? {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    VStack(spacing: 0) {
        ClipItemRow(
            item: ClipItem(
                id: 1,
                createdAt: Date(),
                type: .text,
                textContent: "Hello, World! This is a sample clipboard item.",
                imagePath: nil,
                sourceBundleId: "com.apple.Safari",
                contentHash: "abc123",
                pinned: false,
                protected: false,
                byteSize: 100
            ),
            isSelected: false,
            onCopy: {},
            onDelete: {},
            onTogglePin: {}
        )
        
        Divider()
        
        ClipItemRow(
            item: ClipItem(
                id: 2,
                createdAt: Date().addingTimeInterval(-3600),
                type: .image,
                textContent: nil,
                imagePath: "test.png",
                sourceBundleId: "com.apple.Preview",
                contentHash: "img123",
                pinned: false,
                protected: false,
                byteSize: 256000
            ),
            isSelected: true,
            onCopy: {},
            onDelete: {},
            onTogglePin: {}
        )
    }
    .frame(width: 350)
}
