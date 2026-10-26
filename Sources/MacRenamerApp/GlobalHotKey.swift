import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey via Carbon's RegisterEventHotKey — no Accessibility permission needed.
///
/// The app registers it only while Finder is the frontmost app and unregisters it otherwise,
/// so everywhere else the key combination keeps doing whatever it normally does.
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var registeredPreset: HotKeyPreset?

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        if registeredPreset == preset, hotKeyRef != nil { return true }
        unregister()
        guard let combo = preset.carbon else { return true }
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x4D52_4E4D), id: 1) // 'MRNM'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Mac_Renamer: could not register hotkey \(preset.title) (OSStatus \(status))")
            return false
        }
        hotKeyRef = ref
        registeredPreset = preset
        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredPreset = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { GlobalHotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &ref)
        if status == noErr {
            handlerRef = ref
        } else {
            NSLog("Mac_Renamer: could not install the hotkey handler (OSStatus \(status))")
        }
    }
}
