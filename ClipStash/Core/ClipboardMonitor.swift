import Foundation
import AppKit
import CryptoKit
import Combine

/// Read-only pasteboard surface, allowing polling without the system clipboard in tests.
protocol ClipboardPasteboard {
    var changeCount: Int { get }
    var types: [NSPasteboard.PasteboardType]? { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    func data(forType dataType: NSPasteboard.PasteboardType) -> Data?
}

extension NSPasteboard: ClipboardPasteboard {}

protocol ClipboardCaptureSettings {
    var bytePreserveMode: Bool { get }
    var textMaxBytes: Int { get }
    var imageMaxBytes: Int { get }
    var dedupEnabled: Bool { get }
    var historyLimit: Int { get }
    var saveImages: Bool { get }
    var ignoreConcealed: Bool { get }
    var ignoreTransient: Bool { get }
    func isIgnored(bundleId: String?) -> Bool
}

extension AppSettings: ClipboardCaptureSettings {}

/// Monitors NSPasteboard for changes and saves to storage
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()
    
    @Published private(set) var isRunning = false
    
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastWriteTime: Date = .distantPast
    private let debounceInterval: TimeInterval = 0.5
    private let pollInterval: TimeInterval = 0.3
    
    private let pasteboard: ClipboardPasteboard
    private let settings: ClipboardCaptureSettings
    private let storage: StorageManager
    private let now: () -> Date
    private let sourceBundleId: () -> String?
    private var isProcessing = false
    private let workspaceNotifications: NotificationCenter?
    private var workspaceObserver: NSObjectProtocol?
    private var foregroundBundleId: String?
    private var captureEpoch: UInt64 = 0
    private(set) var monitoringGeneration: UInt64 = 0
    var hasWorkspaceObserver: Bool { workspaceObserver != nil }

    private convenience init() {
        self.init(
            pasteboard: NSPasteboard.general,
            settings: AppSettings.shared,
            storage: StorageManager.shared,
            now: Date.init,
            sourceBundleId: { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
            workspaceNotifications: NSWorkspace.shared.notificationCenter
        )
    }

    init(
        pasteboard: ClipboardPasteboard,
        settings: ClipboardCaptureSettings,
        storage: StorageManager,
        now: @escaping () -> Date,
        sourceBundleId: @escaping () -> String?,
        workspaceNotifications: NotificationCenter? = nil
    ) {
        self.pasteboard = pasteboard
        self.settings = settings
        self.storage = storage
        self.now = now
        self.sourceBundleId = sourceBundleId
        self.workspaceNotifications = workspaceNotifications
    }
    
    // MARK: - Lifecycle
    
    func start() {
        guard !isRunning else { return }
        monitoringGeneration &+= 1
        captureEpoch &+= 1
        let generation = monitoringGeneration
        foregroundBundleId = sourceBundleId()
        lastChangeCount = pasteboard.changeCount
        isRunning = true

        if let center = workspaceNotifications {
            workspaceObserver = center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                // Workspace's event names the incoming app; frontmostApplication
                // can still be the outgoing app. Main delivery must not Task-hop
                // behind a timer poll of the same pending pasteboard change.
                MainActor.assumeIsolated {
                    self?.handleApplicationActivation(bundleId: app.bundleIdentifier, generation: generation)
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollIfCurrentGeneration(generation)
            }
        }
    }

    func stop() {
        // Invalidate queued callbacks before unregistering their sources.
        monitoringGeneration &+= 1
        captureEpoch &+= 1
        isRunning = false
        timer?.invalidate()
        timer = nil
        if let workspaceObserver { workspaceNotifications?.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        foregroundBundleId = nil
    }

    deinit {
        timer?.invalidate()
        if let workspaceObserver { workspaceNotifications?.removeObserver(workspaceObserver) }
    }

    /// Shared by the real synchronous workspace callback and deterministic checks.
    func handleApplicationActivation(bundleId: String?, generation: UInt64) {
        guard isRunning, generation == monitoringGeneration else { return }
        let previous = foregroundBundleId
        foregroundBundleId = bundleId
        if settings.isIgnored(bundleId: previous) || settings.isIgnored(bundleId: bundleId) {
            // Conservatively discard pending content at an excluded foreground
            // boundary. Public pasteboard APIs do not establish writer identity.
            lastChangeCount = pasteboard.changeCount
            captureEpoch &+= 1
        }
    }

    func pollIfCurrentGeneration(_ generation: UInt64) async {
        guard isRunning, generation == monitoringGeneration else { return }
        await checkPasteboard()
    }

    // MARK: - Polling
    
    /// One serialized poll; internal so tests can advance a synthetic clock explicitly.
    func checkPasteboard() async {
        guard !isProcessing else { return }
        let currentChangeCount = pasteboard.changeCount

        guard currentChangeCount != lastChangeCount else { return }
        // Excluded changes must be consumed immediately: a later focus change
        // must not make an ignored application's deferred copy eligible.
        let sourceBundleId = sourceBundleId()
        // The activation event can precede frontmostApplication catching up.
        // Keep the observed exclusion in force for new changes during that gap.
        if isSensitiveContent(pasteboard) || settings.isIgnored(bundleId: sourceBundleId)
            || settings.isIgnored(bundleId: foregroundBundleId) {
            lastChangeCount = currentChangeCount
            return
        }

        // Leave a throttled change pending so the next poll can capture it.
        guard now().timeIntervalSince(lastWriteTime) >= debounceInterval else { return }
        lastChangeCount = currentChangeCount

        isProcessing = true
        defer { isProcessing = false }
        let epoch = captureEpoch
        await processPasteboard(sourceBundleId: sourceBundleId, epoch: epoch, changeCount: currentChangeCount)
        if epoch == captureEpoch { lastWriteTime = now() }
    }

    // MARK: - Processing
    
    private func processPasteboard(sourceBundleId: String?, epoch: UInt64, changeCount: Int) async {
        // Try to get text content
        if let text = pasteboard.string(forType: .string) {
            // Pasteboard reads can cross an external replacement or reveal new
            // sensitive types. Never apply the earlier policy to that snapshot.
            guard pasteboard.changeCount == changeCount, !isSensitiveContent(pasteboard),
                  pasteboard.changeCount == changeCount else { return }
            await processText(text, sourceBundleId: sourceBundleId, epoch: epoch)
            return
        }
        
        // Try to get image content (if enabled)
        if settings.saveImages {
            if let imageData = getImageData(from: pasteboard) {
                guard pasteboard.changeCount == changeCount, !isSensitiveContent(pasteboard),
                      pasteboard.changeCount == changeCount else { return }
                await processImage(imageData, sourceBundleId: sourceBundleId, epoch: epoch)
            }
        }
    }
    
    private func processText(_ text: String, sourceBundleId: String?, epoch: UInt64) async {
        // Apply byte-preserve mode
        let content = settings.bytePreserveMode ? text : text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip empty content
        guard !content.isEmpty else { return }
        
        // Check size limit
        let byteSize = content.utf8.count
        guard byteSize <= settings.textMaxBytes else { return }
        
        // Compute hash for deduplication
        let hash = await computeHash(type: "text", data: Data(content.utf8))
        guard epoch == captureEpoch else { return }
        
        // Check deduplication
        if settings.dedupEnabled {
            do {
                if try await storage.exists(contentHash: hash) {
                    return
                }
            } catch {
                // Continue on error
            }
        }
        
        // A workspace boundary or Stop can invalidate preparation across awaits.
        guard epoch == captureEpoch else { return }
        // Insert into storage
        do {
            _ = try await storage.insert(
                type: .text,
                textContent: content,
                imageData: nil,
                sourceBundleId: sourceBundleId,
                contentHash: hash,
                byteSize: byteSize
            )
            
            // Evict if over limit
            try await storage.evict(limit: settings.historyLimit)
        } catch {
            print("ClipboardMonitor: Failed to save text: \(error)")
        }
    }
    
    private func processImage(_ imageData: Data, sourceBundleId: String?, epoch: UInt64) async {
        // Check size limit
        let byteSize = imageData.count
        guard byteSize <= settings.imageMaxBytes else { return }
        
        // Compute hash for deduplication
        let hash = await computeHash(type: "image", data: imageData)
        guard epoch == captureEpoch else { return }
        
        // Check deduplication
        if settings.dedupEnabled {
            do {
                if try await storage.exists(contentHash: hash) {
                    return
                }
            } catch {
                // Continue on error
            }
        }
        
        // A workspace boundary or Stop can invalidate preparation across awaits.
        guard epoch == captureEpoch else { return }
        // Insert into storage
        do {
            _ = try await storage.insert(
                type: .image,
                textContent: nil,
                imageData: imageData,
                sourceBundleId: sourceBundleId,
                contentHash: hash,
                byteSize: byteSize
            )
            
            // Evict if over limit
            try await storage.evict(limit: settings.historyLimit)
        } catch {
            print("ClipboardMonitor: Failed to save image: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func isSensitiveContent(_ pasteboard: ClipboardPasteboard) -> Bool {
        let types = pasteboard.types ?? []

        // Check for concealed content (password managers) if setting enabled
        if settings.ignoreConcealed {
            if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) {
                return true
            }
        }

        // Check for transient content if setting enabled
        if settings.ignoreTransient {
            if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) {
                return true
            }
        }

        return false
    }
    
    private func getImageData(from pasteboard: ClipboardPasteboard) -> Data? {
        // Try TIFF first (most common)
        if let data = pasteboard.data(forType: .tiff) {
            return data
        }
        
        // Try PNG
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        
        return nil
    }
    
    private func computeHash(type: String, data: Data) async -> String {
        return await Task.detached(priority: .userInitiated) {
            var hasher = SHA256()
            hasher.update(data: Data(type.utf8))
            hasher.update(data: data)
            let digest = hasher.finalize()
            return digest.map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
