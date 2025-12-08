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
