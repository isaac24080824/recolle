import AppKit
import Carbon

final class GlobalHotKey {
    static let display = "⌥W"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    // Carbon takes a physical key code. Resolve the letter on the active layout
    // so Option+W works on French AZERTY as well as QWERTY keyboards.
    static func keyCodeForW() -> UInt32? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let property = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(property,to: CFData.self)
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        for key in UInt16(0)..<128 {
            var deadKey: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0,count: 8)
            let status = UCKeyTranslate(layout,key,UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),OptionBits(kUCKeyTranslateNoDeadKeysMask),&deadKey,chars.count,&length,&chars)
            if status == noErr, String(utf16CodeUnits: chars,count: length).lowercased() == "w" { return UInt32(key) }
        }
        return nil
    }

    func register() -> Bool {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard let keyCode = Self.keyCodeForW() else { return false }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), { _,_,data in
                guard let data else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(data).takeUnretainedValue()
                DispatchQueue.main.async { owner.action?() }
                return noErr
            },1,&event,context,&handler)
            guard status == noErr else { return false }
        }
        let id = EventHotKeyID(signature: 0x5245434C,id: 1)
        return RegisterEventHotKey(keyCode,UInt32(optionKey),id,GetApplicationEventTarget(),0,&hotKey) == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
