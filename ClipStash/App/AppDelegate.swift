import AppKit

/// Application delegate for lifecycle management
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize storage
        Task {
            do {
                try await StorageManager.shared.open()
                print("ClipStash: Database opened successfully")
                print("ClipStash: FTS5 available: \(await StorageManager.shared.isFTS5Available)")
            } catch {
                print("ClipStash: Failed to open database: \(error)")
            }
        }
        
        // Start clipboard monitoring
        Task { @MainActor in
            ClipboardMonitor.shared.start()
            print("ClipStash: Clipboard monitoring started")
        }
        
        // Hide dock icon (menu bar only)
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Stop monitoring
        Task { @MainActor in
            ClipboardMonitor.shared.stop()
        }
        
        // Close database
        Task {
            await StorageManager.shared.close()
        }
    }
}
