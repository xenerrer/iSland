import AppKit
import Carbon.HIToolbox
import IslandCore

/// Global shortcuts that exist only while a question is waiting, so they never get in the way otherwise:
/// ⌥⌘Y allow, ⌥⌘N deny, ⌥⌘T hand it back to the terminal.
/// Carbon hot keys need no permission. If another app already owns a combination, that one is simply skipped.
@MainActor
final class ApprovalHotkeys {
    private struct Binding {
        let id: UInt32
        let keyCode: Int
        let decision: Decision
    }

    private static let signature = OSType(0x6953_4C44) // 'iSLD'
    private let bindings = [
        Binding(id: 1, keyCode: kVK_ANSI_Y, decision: .allow),
        Binding(id: 2, keyCode: kVK_ANSI_N, decision: .deny),
        Binding(id: 3, keyCode: kVK_ANSI_T, decision: .terminal),
    ]
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let onDecision: (Decision) -> Void

    init(onDecision: @escaping (Decision) -> Void) {
        self.onDecision = onDecision
    }

    /// Allow and deny are the two the card advertises; true when both are registered.
    var isActive: Bool { registered[1] != nil && registered[2] != nil }

    func activate() {
        guard registered.isEmpty else { return }
        installHandlerIfNeeded()
        let modifiers = UInt32(optionKey | cmdKey)
        for binding in bindings {
            var reference: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: binding.id)
            let status = RegisterEventHotKey(UInt32(binding.keyCode), modifiers, id, GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference { registered[binding.id] = reference }
            else { NSLog("iSland: shortcut ⌥⌘%@ unavailable (status %d)", binding.decision.rawValue, status) }
        }
        NSLog("iSland: approval shortcuts registered: %d of %d", registered.count, bindings.count)
    }

    func deactivate() {
        for reference in registered.values { UnregisterEventHotKey(reference) }
        registered.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let hotkeys = Unmanaged<ApprovalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async { MainActor.assumeIsolated { hotkeys.fire(id) } }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func fire(_ id: UInt32) {
        guard let binding = bindings.first(where: { $0.id == id }) else { return }
        onDecision(binding.decision)
    }
}
