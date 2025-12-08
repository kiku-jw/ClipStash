import SwiftUI

/// Row view for a single clipboard item
struct ClipItemRow: View {
    let item: ClipItem
    let isSelected: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onTogglePin: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Pin indicator or type icon
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Image(systemName: item.type == .text ? "doc.text" : "photo")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                // Content preview
                Text(item.preview)
                    .font(.system(.body))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
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
                type: .text,
                textContent: "Pinned item example",
                imagePath: nil,
                sourceBundleId: "com.apple.Notes",
                contentHash: "def456",
                pinned: true,
                protected: false,
                byteSize: 50
            ),
            isSelected: true,
            onCopy: {},
            onDelete: {},
            onTogglePin: {}
        )
    }
    .frame(width: 350)
}
