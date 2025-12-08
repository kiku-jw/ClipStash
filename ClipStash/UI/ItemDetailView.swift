import SwiftUI
import AppKit

/// Detail view for displaying full clipboard item content
struct ItemDetailView: View {
    let item: ClipItem
    @Environment(\.dismiss) private var dismiss
    @State private var image: NSImage?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let appName = item.sourceAppName {
                    Text(appName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(item.formattedTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Content
            if item.type == .image {
                imageContent
            } else {
                textContent
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Copy Full Content") {
                    copyToClipboard()
                }
                .buttonStyle(.borderedProminent)
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadImage()
        }
    }
    
    private var textContent: some View {
        ScrollView {
            Text(item.textContent ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    private var imageContent: some View {
        Group {
            if let image = image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack {
                    ProgressView()
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func loadImage() {
        guard item.type == .image, let imagePath = item.imagePath else { return }
        
        Task {
            // Use StorageManager to get full URL (imagePath is relative)
            let url = await StorageManager.shared.imageURL(for: imagePath)
            if let nsImage = NSImage(contentsOf: url) {
                await MainActor.run {
                    self.image = nsImage
                }
            }
        }
    }
    
    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        if item.type == .image, let image = image {
            pb.writeObjects([image])
        } else if let content = item.textContent {
            pb.setString(content, forType: .string)
        }
        
        dismiss()
    }
}
