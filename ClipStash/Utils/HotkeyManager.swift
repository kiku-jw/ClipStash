import Carbon
import AppKit

/// Global hotkey manager using Carbon API
final class HotkeyManager {
    static let shared = HotkeyManager()
    
    private var hotkeyRef: EventHotKeyRef?
    private var hotkeyID = EventHotKeyID()
    private var eventHandler: EventHandlerRef?
    
    // Callback for hotkey press
    var onHotkeyPressed: (() -> Void)?
    
    private init() {
        hotkeyID.signature = OSType(0x434C5053) // "CLPS"
        hotkeyID.id = 1
    }
    
    deinit {
        unregister()
    }
    
    /// Register global hotkey (default: ⌘⇧V)
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        // Unregister existing hotkey if any
        unregister()
        
        // Install event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handlerCallback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            
            if hotKeyID.id == manager.hotkeyID.id {
                DispatchQueue.main.async {
                    manager.onHotkeyPressed?()
                }
            }
            
            return noErr
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            handlerCallback,
            1,
            &eventSpec,
            selfPtr,
            &eventHandler
        )
        
        // Register hotkey
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }
    
    /// Unregister global hotkey
    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
    
    /// Check if hotkey is registered
    var isRegistered: Bool {
        hotkeyRef != nil
    }
}
