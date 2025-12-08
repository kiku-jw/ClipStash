import SwiftUI
import ServiceManagement

/// Settings view with detailed, organized tabs
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var newBundleId = ""
    @State private var diagnostics: Diagnostics?
    @State private var showResetConfirmation = false
    
    struct Diagnostics {
        let itemCount: Int
        let pinnedCount: Int
        let dbSize: Int64
        let imagesSize: Int64
        let fts5Available: Bool
        let isMonitoring: Bool
    }
    
    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            captureTab
                .tabItem {
                    Label("Capture", systemImage: "arrow.down.doc")
                }
            
            limitsTab
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
            
            privacyTab
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
            
            exportTab
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            
            diagnosticsTab
                .tabItem {
                    Label("Advanced", systemImage: "wrench.and.screwdriver")
                }
            
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        Form {
            Section {
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.launchAtLogin) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .font(.body)
                                Text("Start ClipStash automatically when you log in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: settings.launchAtLogin) { oldValue, newValue in
                            updateLaunchAtLogin(enabled: newValue)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.globalHotkeyEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Global Hotkey")
                                    .font(.body)
                                Text("⌘⇧V to open ClipStash from anywhere")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
                
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Move app to /Applications for Launch at Login to work reliably.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
    }
    
    // MARK: - Capture Tab
    
    private var captureTab: some View {
        Form {
            Section {
                GroupBox(label: Label("Content Types", systemImage: "doc.on.doc")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            Text("Text")
                            Spacer()
                            Text("Always captured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.saveImages) {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.purple)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Images")
                                    Text("Capture screenshots and copied images")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                
                GroupBox(label: Label("Processing", systemImage: "wand.and.stars")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.dedupEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Skip Duplicates")
                                Text("Don't save identical content twice")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.bytePreserveMode) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Preserve Whitespace")
                                Text("Keep exact spaces, tabs, and newlines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Limits Tab
    
    private var limitsTab: some View {
        Form {
            Section {
                GroupBox(label: Label("History Size", systemImage: "clock.arrow.circlepath")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Maximum Items")
                            Spacer()
                            Text("\(settings.historyLimit)")
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(settings.historyLimit) },
                            set: { settings.historyLimit = Int($0) }
                        ), in: 100...2000, step: 100)
                        
                        HStack {
                            Text("100")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("2000")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                }
                
                GroupBox(label: Label("Size Limits", systemImage: "arrow.up.arrow.down")) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.blue)
                                Text("Text")
                                Spacer()
                                Text(formatBytes(settings.textMaxBytes))
                                    .font(.headline)
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(settings.textMaxBytes) },
                                set: { settings.textMaxBytes = Int($0) }
                            ), in: 10_000...1_000_000, step: 10_000)
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "photo")
                                    .foregroundColor(.purple)
                                Text("Image")
                                Spacer()
                                Text(formatBytes(settings.imageMaxBytes))
                                    .font(.headline)
                                    .foregroundColor(.purple)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(settings.imageMaxBytes) },
                                set: { settings.imageMaxBytes = Int($0) }
                            ), in: 1_000_000...20_000_000, step: 1_000_000)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Privacy Tab
    
    private var privacyTab: some View {
        Form {
            Section {
                GroupBox(label: Label("Automatic Protection", systemImage: "shield.checkered")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $settings.ignoreConcealed) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ignore Password Managers")
                                    .font(.body)
                                Text("Skip clipboard items marked as concealed (1Password, etc.)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        Toggle(isOn: $settings.ignoreTransient) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ignore Transient Items")
                                    .font(.body)
                                Text("Skip temporary clipboard content")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }
                
                GroupBox(label: Label("Ignored Apps", systemImage: "app.badge.checkmark")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clipboard from these apps will not be captured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            TextField("com.example.app", text: $newBundleId)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            
                            Button {
                                if !newBundleId.isEmpty {
                                    settings.addIgnoredBundleId(newBundleId)
                                    newBundleId = ""
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .disabled(newBundleId.isEmpty)
                            
                            Button {
                                selectAppFromFinder()
                            } label: {
                                Image(systemName: "folder")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Choose app from Finder")
                        }
                        
                        if !settings.ignoredBundleIds.isEmpty {
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(settings.ignoredBundleIds, id: \.self) { bundleId in
                                        HStack {
                                            if let appName = appName(for: bundleId) {
                                                Text(appName)
                                                    .font(.caption)
                                                    .foregroundColor(.primary)
                                                Text("(\(bundleId))")
                                                    .font(.system(.caption2, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                Text(bundleId)
                                                    .font(.system(.caption, design: .monospaced))
                                            }
                                            Spacer()
                                            Button {
                                                settings.removeIgnoredBundleId(bundleId)
                                            } label: {
                                                Image(systemName: "xmark.circle")
                                                    .foregroundColor(.red.opacity(0.7))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(4)
                                    }
                                }
                            }
                            .frame(maxHeight: 100)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .padding()
    }
    
    private func selectAppFromFinder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select an application to ignore"
        panel.prompt = "Add to Ignore List"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                settings.addIgnoredBundleId(bundleId)
            }
        }
    }
    
    private func appName(for bundleId: String) -> String? {
        // Try to find app name from common locations
        let paths = ["/Applications", "/System/Applications", "/Applications/Utilities"]
        for basePath in paths {
            if let apps = try? FileManager.default.contentsOfDirectory(atPath: basePath) {
                for app in apps where app.hasSuffix(".app") {
                    let appPath = "\(basePath)/\(app)"
                    if let bundle = Bundle(path: appPath), bundle.bundleIdentifier == bundleId {
                        return bundle.infoDictionary?["CFBundleName"] as? String ?? app.replacingOccurrences(of: ".app", with: "")
                    }
                }
            }
        }
        return nil
    }
    
    // MARK: - Export Tab
    
    private var exportTab: some View {
        Form {
            Section {
                // Scope picker
                HStack {
                    Text("Items to export")
                    Spacer()
                    Picker("", selection: $settings.exportScope) {
                        Text("50").tag(50)
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("500").tag(500)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                
                // Format picker
                HStack {
                    Text("Format")
                    Spacer()
                    Picker("", selection: $settings.exportFormat) {
                        Text("Markdown").tag("markdown")
                        Text("Plain Text").tag("plaintext")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                
                // Toggles
                Toggle("Export pinned only", isOn: $settings.exportPinnedOnly)
                Toggle("Skip export warning", isOn: $settings.exportWarningShown)
                
                // Info
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Large exports auto-split at ~180KB for NotebookLM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Diagnostics Tab
    
    private var diagnosticsTab: some View {
        Form {
            Section {
                GroupBox(label: Label("Status", systemImage: "heart.text.square")) {
                    VStack(spacing: 8) {
                        if let diag = diagnostics {
                            StatusRow(icon: "doc.on.doc", label: "Total Items", value: "\(diag.itemCount)")
                            StatusRow(icon: "pin", label: "Pinned", value: "\(diag.pinnedCount)")
                            StatusRow(icon: "externaldrive", label: "Database", value: formatBytes(Int(diag.dbSize)))
                            StatusRow(icon: "photo.stack", label: "Images", value: formatBytes(Int(diag.imagesSize)))
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(8)
                }
                
                HStack {
                    Button {
                        Task { await loadDiagnostics() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Clear All History", systemImage: "trash")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .onAppear {
            Task { await loadDiagnostics() }
        }
        .confirmationDialog("Clear All History?", isPresented: $showResetConfirmation) {
            Button("Clear All", role: .destructive) {
                Task {
                    try? await StorageManager.shared.clearAll(keepPinned: false)
                    await loadDiagnostics()
                }
            }
            Button("Keep Pinned Items") {
                Task {
                    try? await StorageManager.shared.clearAll(keepPinned: true)
                    await loadDiagnostics()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Helpers
    
    private func loadDiagnostics() async {
        let itemCount = (try? await StorageManager.shared.count()) ?? 0
        let pinnedCount = itemCount - ((try? await StorageManager.shared.countUnpinned()) ?? 0)
        let dbSize = await StorageManager.shared.getDatabaseSize()
        let imagesSize = await StorageManager.shared.getImagesFolderSize()
        let fts5Available = await StorageManager.shared.isFTS5Available
        let isMonitoring = await MainActor.run { ClipboardMonitor.shared.isRunning }
        
        await MainActor.run {
            diagnostics = Diagnostics(
                itemCount: itemCount,
                pinnedCount: pinnedCount,
                dbSize: dbSize,
                imagesSize: imagesSize,
                fts5Available: fts5Available,
                isMonitoring: isMonitoring
            )
        }
    }
    
    private func updateLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}

// MARK: - Status Row Component

struct StatusRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundColor(.secondary)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - About Tab

extension SettingsView {
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // App Icon
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("ClipStash")
                .font(.title.bold())
            
            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Button {
                    if let url = URL(string: "https://kikuai.dev") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Made by KikuAI Lab")
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Button {
                    if let url = URL(string: "https://github.com/kiku-jw/ClipStash") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                        Text("View on GitHub")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(width: 200)
            
            VStack(spacing: 8) {
                Text("Support Development")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    SupportButton(title: "Gumroad", url: "https://kiku0.gumroad.com/coffee")
                    SupportButton(title: "BMC", url: "https://buymeacoffee.com/kiku")
                    SupportButton(title: "Thanks", url: "https://thanks.dev/d/gh/kiku-jw")
                    SupportButton(title: "Ko-fi", url: "https://ko-fi.com/kiku_jw")
                }
            }
            
            Spacer()
        }
    }
}

struct SupportButton: View {
    let title: String
    let url: String
    
    var body: some View {
        Button {
            if let buttonUrl = URL(string: url) {
                NSWorkspace.shared.open(buttonUrl)
            }
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .help(url)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings.shared)
}
