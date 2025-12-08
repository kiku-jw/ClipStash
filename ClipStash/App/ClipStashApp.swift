import SwiftUI

/// Main app entry point with MenuBarExtra
@main
struct ClipStashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Menu bar app — no main window
        MenuBarExtra {
            PopoverView()
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
        .menuBarExtraStyle(.window)
    }
}
