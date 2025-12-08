import SwiftUI
import ServiceManagement

/// Settings view for configuring ClipStash
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = Settings.shared
    
    @State private var newIgnoreBundleId = ""
    @State private var showingDiagnostics = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            Form {
                // History section
                Section("History") {
                    HStack {
                        Text("History Limit")
                        Spacer()
                        TextField("", value: $settings.historyLimit, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { settings.validateHistoryLimit() }
                        Text("items")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Text Max Size")
                        Spacer()
                        TextField("", value: $settings.textMaxBytes, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { settings.validateTextMaxBytes() }
                        Text("bytes")
                            .foregroundColor(.secondary)
                    }
                    
                    Toggle("Save Images", isOn: $settings.saveImages)
                    
                    if settings.saveImages {
                        HStack {
                            Text("Image Max Size")
                            Spacer()
                            TextField("", value: $settings.imageMaxBytes, format: .number)
                                .frame(width: 100)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { settings.validateImageMaxBytes() }
                            Text("bytes")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Behavior section
                Section("Behavior") {
                    Toggle("Deduplication", isOn: $settings.dedupEnabled)
                        .help("Skip duplicate clipboard content")
                    
                    Toggle("Byte Preserve Mode", isOn: $settings.bytePreserveMode)
                        .help("Keep exact whitespace, don't trim")
                    
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, newValue in
                            updateLaunchAtLogin(newValue)
                        }
                }
                
                // Ignore List section
                Section("Ignore List") {
                    Text("Apps whose clipboard content will be ignored:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(settings.ignoredBundleIds, id: \.self) { bundleId in
                        HStack {
                            Text(bundleId)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(action: { settings.removeIgnoredBundleId(bundleId) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        TextField("Bundle ID (e.g., com.1password.1password)", text: $newIgnoreBundleId)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: {
                            if !newIgnoreBundleId.isEmpty {
                                settings.addIgnoredBundleId(newIgnoreBundleId)
                                newIgnoreBundleId = ""
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .disabled(newIgnoreBundleId.isEmpty)
                    }
                }
                
                // About section
                Section("About") {
                    HStack {
                        Text("ClipStash")
                        Spacer()
                        Text("v1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Show Diagnostics") {
                        showingDiagnostics = true
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: 500)
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsView()
        }
    }
    
    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle on error
            settings.launchAtLogin = !enabled
            print("Failed to update launch at login: \(error)")
        }
    }
}

// MARK: - Diagnostics View

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var itemCount = 0
    @State private var dbSize: Int64 = 0
    @State private var imagesSize: Int64 = 0
    @State private var fts5Available = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Diagnostics")
                .font(.headline)
            
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Total Items:")
                    Text("\(itemCount)")
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Database Size:")
                    Text(formatBytes(dbSize))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("Images Folder:")
                    Text(formatBytes(imagesSize))
                        .foregroundColor(.secondary)
                }
                
                GridRow {
                    Text("FTS5 Search:")
                    Text(fts5Available ? "Available" : "Fallback (LIKE)")
                        .foregroundColor(fts5Available ? .green : .orange)
                }
            }
            .padding()
            
            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
            loadDiagnostics()
        }
    }
    
    private func loadDiagnostics() {
        Task {
            do {
                itemCount = try await StorageManager.shared.count()
                dbSize = await StorageManager.shared.getDatabaseSize()
                imagesSize = await StorageManager.shared.getImagesFolderSize()
                fts5Available = await StorageManager.shared.isFTS5Available
            } catch {
                // Ignore
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    SettingsView()
}
