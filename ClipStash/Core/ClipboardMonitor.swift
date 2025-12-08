import Foundation
import AppKit
import CryptoKit

/// Monitors NSPasteboard for changes and saves to storage
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published private(set) var isRunning = false
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastWriteTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5
    private let pollInterval: TimeInterval = 0.3
    
    private let settings = Settings.shared
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isRunning else { return }
        
        lastChangeCount = NSPasteboard.general.changeCount
        
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPasteboard()
            }
        }
        
        isRunning = true
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }
    
    // MARK: - Polling
    
    private func checkPasteboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Debounce: skip if last write was too recent
        let now = Date()
        guard now.timeIntervalSince(lastWriteTime) >= debounceInterval else { return }
        
        // Process pasteboard
        Task {
            await processPasteboard()
            await MainActor.run {
                self.lastWriteTime = Date()
            }
        }
    }
    
    // MARK: - Processing
    
    private func processPasteboard() async {
        let pasteboard = NSPasteboard.general
        
        // Check for sensitive content indicators
        if isSensitiveContent(pasteboard) {
            return
        }
        
        // Check ignore list
        if let frontmostApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.isIgnored(bundleId: frontmostApp) {
            return
        }
        
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        
        // Try to get text content
        if let text = pasteboard.string(forType: .string) {
            await processText(text, sourceBundleId: sourceBundleId)
            return
        }
        
        // Try to get image content (if enabled)
        if settings.saveImages {
            if let imageData = getImageData(from: pasteboard) {
                await processImage(imageData, sourceBundleId: sourceBundleId)
            }
        }
    }
    
    private func processText(_ text: String, sourceBundleId: String?) async {
        // Apply byte-preserve mode
        let content = settings.bytePreserveMode ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty content
        guard !content.isEmpty else { return }
        
        // Check size limit
        let byteSize = content.utf8.count
        guard byteSize <= settings.textMaxBytes else { return }
        
        // Compute hash for deduplication
        let hash = computeHash(type: "text", data: Data(content.utf8))
        
        // Check deduplication
        if settings.dedupEnabled {
            do {
                if try await StorageManager.shared.exists(contentHash: hash) {
                    return
                }
            } catch {
                // Continue on error
            }
        }
        
        // Insert into storage
        do {
            _ = try await StorageManager.shared.insert(
                type: .text,
                textContent: content,
                imageData: nil,
                sourceBundleId: sourceBundleId,
                contentHash: hash,
                byteSize: byteSize
            )
            
            // Evict if over limit
            try await StorageManager.shared.evict(limit: settings.historyLimit)
        } catch {
            print("ClipboardMonitor: Failed to save text: \(error)")
        }
    }
    
    private func processImage(_ imageData: Data, sourceBundleId: String?) async {
        // Check size limit
        let byteSize = imageData.count
        guard byteSize <= settings.imageMaxBytes else { return }
        
        // Compute hash for deduplication
        let hash = computeHash(type: "image", data: imageData)
        
        // Check deduplication
        if settings.dedupEnabled {
            do {
                if try await StorageManager.shared.exists(contentHash: hash) {
                    return
                }
            } catch {
                // Continue on error
            }
        }
        
        // Insert into storage
        do {
            _ = try await StorageManager.shared.insert(
                type: .image,
                textContent: nil,
                imageData: imageData,
                sourceBundleId: sourceBundleId,
                contentHash: hash,
                byteSize: byteSize
            )
            
            // Evict if over limit
            try await StorageManager.shared.evict(limit: settings.historyLimit)
        } catch {
            print("ClipboardMonitor: Failed to save image: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func isSensitiveContent(_ pasteboard: NSPasteboard) -> Bool {
        let types = pasteboard.types ?? []
        
        // Check for concealed content (password managers)
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) {
            return true
        }
        
        // Check for transient content
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) {
            return true
        }
        
        return false
    }
    
    private func getImageData(from pasteboard: NSPasteboard) -> Data? {
        // Try TIFF first (most common)
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        
        // Try PNG
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        
        return nil
    }
    
    private func computeHash(type: String, data: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(type.utf8))
        hasher.update(data: data)
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
