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
                
                // Bottom bar with actions
                HStack(spacing: 12) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("About ClipStash")
                    
                    SettingsLink {
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
                    .interactiveDismissDisabled()
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
            
            // GitHub link
            Button {
                if let url = URL(string: "https://github.com/kiku-jw/ClipStash") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption)
                    Text("View on GitHub")
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
            
            // Support links with service names
            VStack(spacing: 8) {
                Text("Support Development")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 6) {
                    DonateButton(title: "Gumroad", url: "https://kiku0.gumroad.com/coffee")
                    DonateButton(title: "BMC", url: "https://buymeacoffee.com/kiku")
                    DonateButton(title: "Thanks", url: "https://thanks.dev/d/gh/kiku-jw")
                    DonateButton(title: "Ko-fi", url: "https://ko-fi.com/kiku_jw")
                }
            }
            
            Spacer()
                .frame(height: 12)
            
            // Close button
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.escape)
        }
        .padding(24)
        .frame(width: 320, height: 380)
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
                .font(.caption)
                .fontWeight(.medium)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .help(url)
    }
}

#Preview("About") {
    AboutView()
}
