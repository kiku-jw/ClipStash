import Foundation
import SwiftUI

/// App settings with UserDefaults persistence
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // MARK: - Keys
    
    private enum Keys {
        static let historyLimit = "historyLimit"
        static let textMaxBytes = "textMaxBytes"
        static let imageMaxBytes = "imageMaxBytes"
        static let dedupEnabled = "dedupEnabled"
        static let bytePreserveMode = "bytePreserveMode"
        static let saveImages = "saveImages"
        static let ignoredBundleIds = "ignoredBundleIds"
        static let launchAtLogin = "launchAtLogin"
        static let globalHotkeyEnabled = "globalHotkeyEnabled"
        static let exportWarningShown = "exportWarningShown"
        static let ignoreConcealed = "ignoreConcealed"
        static let ignoreTransient = "ignoreTransient"
    }
    
    // MARK: - Settings
    
    /// Maximum number of items to keep in history (100-2000)
    @AppStorage(Keys.historyLimit) var historyLimit: Int = 500
    
    /// Maximum text size in bytes (10KB - 1MB)
    @AppStorage(Keys.textMaxBytes) var textMaxBytes: Int = 200_000
    
    /// Maximum image size in bytes (1MB - 20MB)
    @AppStorage(Keys.imageMaxBytes) var imageMaxBytes: Int = 5_000_000
    
    /// Enable deduplication (skip identical content)
    @AppStorage(Keys.dedupEnabled) var dedupEnabled: Bool = true
    
    /// Preserve exact bytes (no whitespace trimming)
    @AppStorage(Keys.bytePreserveMode) var bytePreserveMode: Bool = false
    
    /// Also capture images from clipboard
    @AppStorage(Keys.saveImages) var saveImages: Bool = true
    
    /// Launch at login
    @AppStorage(Keys.launchAtLogin) var launchAtLogin: Bool = false
    
    /// Enable global hotkey
    @AppStorage(Keys.globalHotkeyEnabled) var globalHotkeyEnabled: Bool = false
    
    /// Export warning already shown
    @AppStorage(Keys.exportWarningShown) var exportWarningShown: Bool = false
    
    /// Ignore concealed clipboard items (password managers)
    @AppStorage(Keys.ignoreConcealed) var ignoreConcealed: Bool = true
    
    /// Ignore transient clipboard items
    @AppStorage(Keys.ignoreTransient) var ignoreTransient: Bool = true
    
    /// Export scope: number of items (50, 100, 200, 500)
    @AppStorage("exportScope") var exportScope: Int = 100
    
    /// Export format: markdown or plaintext
    @AppStorage("exportFormat") var exportFormat: String = "markdown"
    
    /// Export only pinned items
    @AppStorage("exportPinnedOnly") var exportPinnedOnly: Bool = false
    
    // MARK: - Ignore List
    
    /// Bundle IDs to ignore (stored as JSON array)
    var ignoredBundleIds: [String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Keys.ignoredBundleIds),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Keys.ignoredBundleIds)
                objectWillChange.send()
            }
        }
    }
    
    // MARK: - Validation
    
    /// Clamp historyLimit to valid range
    func validateHistoryLimit() {
        historyLimit = max(100, min(2000, historyLimit))
    }
    
    /// Clamp textMaxBytes to valid range
    func validateTextMaxBytes() {
        textMaxBytes = max(10_000, min(1_000_000, textMaxBytes))
    }
    
    /// Clamp imageMaxBytes to valid range
    func validateImageMaxBytes() {
        imageMaxBytes = max(1_000_000, min(20_000_000, imageMaxBytes))
    }
    
    // MARK: - Ignore List Helpers
    
    func addIgnoredBundleId(_ bundleId: String) {
        var ids = ignoredBundleIds
        if !ids.contains(bundleId) {
            ids.append(bundleId)
            ignoredBundleIds = ids
        }
    }
    
    func removeIgnoredBundleId(_ bundleId: String) {
        var ids = ignoredBundleIds
        ids.removeAll { $0 == bundleId }
        ignoredBundleIds = ids
    }
    
    func isIgnored(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return ignoredBundleIds.contains(bundleId)
    }
}
