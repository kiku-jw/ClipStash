import SwiftUI
import AppKit

@main
struct ClipStashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showAbout = false
    
    var body: some Scene {
        MenuBarExtra {
            VStack(spacing: 0) {
                PopoverView()
                    .environmentObject(appDelegate.viewModel)
                    .environmentObject(AppSettings.shared)
                
                Divider()
                    .padding(.vertical, 4)
                
                // Context menu at bottom
                HStack(spacing: 12) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("About ClipStash")
                    
                    Button {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    
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
            .sheet(isPresented: $showAbout) {
                AboutView()
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

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // App Name
            Text("ClipStash")
                .font(.title.bold())
            
            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
            
            // Description
            Text("Lightweight, privacy-first\nclipboard history manager")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Divider()
                .frame(width: 200)
            
            // Author
            VStack(spacing: 4) {
                Text("Made by")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button {
                    if let url = URL(string: "https://kikuai.dev") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("KikuAI Lab")
                            .font(.headline)
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
            }
            
            Divider()
                .frame(width: 200)
            
            // Support links
            VStack(spacing: 8) {
                Text("Support Development")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    DonateButton(title: "☕", url: "https://kiku0.gumroad.com/coffee")
                    DonateButton(title: "☕", url: "https://buymeacoffee.com/kiku")
                    DonateButton(title: "🙏", url: "https://thanks.dev/d/gh/kiku-jw")
                    DonateButton(title: "💚", url: "https://ko-fi.com/kiku_jw")
                }
            }
            
            Spacer()
                .frame(height: 8)
            
            // Close button
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 300, height: 420)
    }
}

// MARK: - Donate Button

struct DonateButton: View {
    let title: String
    let url: String
    
    var body: some View {
        Button {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text(title)
                .font(.title2)
        }
        .buttonStyle(.plain)
        .padding(6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .help(url)
    }
}

#Preview("About") {
    AboutView()
}
