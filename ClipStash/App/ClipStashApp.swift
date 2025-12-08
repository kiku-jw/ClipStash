import SwiftUI
import AppKit

@main
struct ClipStashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                PopoverView()
                    .environmentObject(appDelegate.viewModel)
                    .environmentObject(AppSettings.shared)
                
                Divider()
                    .padding(.vertical, 4)
                
                // Bottom bar - simplified
                HStack(spacing: 12) {
                    SettingsLink {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Settings (includes About & Export)")
                    
                    Spacer()
                    
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Image(systemName: "power")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Quit ClipStash")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        } label: {
            Image(systemName: "list.clipboard")
        }
        .menuBarExtraStyle(.window)
        
        SwiftUI.Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
        }
    }
}

/// Helper to open a detail window for clipboard items
class DetailWindowController {
    static let shared = DetailWindowController()
    
    private var detailWindow: NSWindow?
    
    func showDetail(for item: ClipItem) {
        // Close existing window if any
        detailWindow?.close()
        
        // Create new window
        let contentView = ItemDetailView(item: item)
        let hostingView = NSHostingController(rootView: contentView)
        
        let window = NSWindow(contentViewController: hostingView)
        window.title = "Clipboard Item"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.level = .floating  // Stay on top
        window.makeKeyAndOrderFront(nil)
        
        // Activate app to bring window to front
        NSApp.activate(ignoringOtherApps: true)
        
        detailWindow = window
    }
}

