import SwiftUI
import AppKit

/// Row view for a clipboard item with image preview
struct ClipItemRow: View {
    let item: ClipItem
    @State private var thumbnailImage: NSImage?
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Thumbnail / Icon
            thumbnailView
                .frame(width: 40, height: 40)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Content preview
                HStack(spacing: 4) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    
                    if item.protected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    
                    Text(item.preview)
                        .lineLimit(2)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                }
                
                // Metadata
                HStack(spacing: 6) {
                    if let appName = item.sourceAppName {
                        HStack(spacing: 2) {
                            Image(systemName: "app.fill")
                                .font(.system(size: 8))
                            Text(appName)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                        .cornerRadius(4)
                    }
                    
                    HStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(item.formattedTime)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(Formatters.formatBytes(item.byteSize))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .task {
            await loadThumbnail()
        }
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        switch item.type {
        case .text:
            // Text icon with accent
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
            }
            
        case .image:
            // Image thumbnail
            if let image = thumbnailImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(6)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "photo.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                }
            }
        }
    }
    
    private func loadThumbnail() async {
        guard item.type == .image, let imagePath = item.imagePath else { return }
        
        let url = await StorageManager.shared.imageURL(for: imagePath)
        
        // Load on background thread
        let image = await Task.detached(priority: .background) {
            guard let image = NSImage(contentsOf: url) else { return nil as NSImage? }
            
            // Create thumbnail (max 80x80 for retina)
            let targetSize = NSSize(width: 80, height: 80)
            let aspectRatio = image.size.width / image.size.height
            
            var thumbnailSize: NSSize
            if aspectRatio > 1 {
                thumbnailSize = NSSize(width: targetSize.width, height: targetSize.width / aspectRatio)
            } else {
                thumbnailSize = NSSize(width: targetSize.height * aspectRatio, height: targetSize.height)
            }
            
            let thumbnail = NSImage(size: thumbnailSize)
            thumbnail.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            thumbnail.unlockFocus()
            
            return thumbnail
        }.value
        
        await MainActor.run {
            self.thumbnailImage = image
        }
    }
    
}

#Preview {
    VStack(spacing: 0) {
        ClipItemRow(item: ClipItem(
            id: 1,
            createdAt: Date(),
            type: .text,
            textContent: "Hello, this is a sample clipboard text that might be a bit longer to show truncation.",
            imagePath: nil,
            sourceBundleId: "com.apple.Safari",
            contentHash: "abc123",
            pinned: true,
            protected: false,
            byteSize: 512
        ))
        
        Divider()
        
        ClipItemRow(item: ClipItem(
            id: 2,
            createdAt: Date().addingTimeInterval(-3600),
            type: .image,
            textContent: nil,
            imagePath: "test.png",
            sourceBundleId: "com.apple.Preview",
            contentHash: "def456",
            pinned: false,
            protected: true,
            byteSize: 102400
        ))
    }
    .frame(width: 320)
    .padding()
}
