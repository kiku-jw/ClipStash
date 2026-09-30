import AppKit
import SwiftUI
import ServiceManagement

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ClipboardViewModel()
    private let isRunningUnitTests = NSClassFromString("XCTestCase") != nil
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A hosted unit test must not monitor the clipboard, open the user's
        // database, or change login-item registration.
        guard !isRunningUnitTests else { return }
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
        guard !isRunningUnitTests else { return }
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
