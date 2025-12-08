import AppKit
import SwiftUI
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ClipboardViewModel()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize storage
        Task {
            do {
                try await StorageManager.shared.open()
            } catch {
                print("Failed to open storage: \(error)")
            }
        }
        
        // Start clipboard monitoring
        ClipboardMonitor.shared.start()
        
        // Setup launch at login
        updateLaunchAtLogin()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ClipboardMonitor.shared.stop()
        
        Task {
            await StorageManager.shared.close()
        }
    }
    
    func updateLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if AppSettings.shared.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
}
