import AppKit
import SwiftUI

/// Opens and closes the island by watching the pointer.
///
/// SwiftUI's onHover needs the window to be key/active, which a non-activating accessory panel never is.
/// Global + local mouse monitors need no permission for mouse movement and work whatever app is in front.
@MainActor
final class HoverController {
    private let store: SessionStore
    private let widgets: Widgets
    private var layout: IslandLayout
    private var screenFrame: NSRect
    /// The display this island lives on.
    private let display: CGDirectDisplayID
    private var monitors: [Any] = []
    private var pending: Task<Void, Never>?
    /// Called with true while the pointer is over an open island. The panel is far bigger than the island, so it
    /// must let every click through except those that land on the island itself.
    var setInteractive: ((Bool) -> Void)?
    /// While in the future, a pointer elsewhere does not close the island.
    private var holdUntil = Date.distantPast
    /// Seconds the pointer rests on the notch before the island opens (a setting).
    var openDelay: TimeInterval = 0.12

    init(store: SessionStore, widgets: Widgets, layout: IslandLayout, screenFrame: NSRect, display: CGDirectDisplayID) {
        self.display = display
        self.store = store
        self.widgets = widgets
        self.layout = layout
        self.screenFrame = screenFrame
    }

    /// The screen or its notch changed (new resolution, display plugged in...).
    func update(layout: IslandLayout, screenFrame: NSRect) {
        self.layout = layout
        self.screenFrame = screenFrame
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }) { monitors.append(monitor) }
        // A click that reaches ANOTHER app while the pointer is over our open island means the panel was still click-through:
        // note it, and fix the cause for the next click.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.clickPassedThrough() }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in self?.pointerMoved() }
            return event
        }) { monitors.append(monitor) }
    }

    /// Keeps the island open for a few seconds even though the pointer is elsewhere: it is how opening the app a second
    /// time shows where the settings gear is. The island closes by itself once the time is up.
    func hold(for seconds: TimeInterval) {
        holdUntil = Date().addingTimeInterval(seconds)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds + 0.1))
            pointerMoved()
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pending?.cancel()
    }

    /// Screen area (AppKit coordinates, origin bottom-left) in which the pointer keeps the island in its current state.
    private var hitRect: NSRect {
        let size = layout.size(for: store, widgets: widgets.presence, display: display)
        let pad: CGFloat = store.isOpen(on: display) ? 16 : 8
        return NSRect(x: screenFrame.midX - size.width / 2 - pad,
                      y: screenFrame.maxY - size.height - pad,
                      width: size.width + 2 * pad,
                      height: size.height + pad + 2) // +2: a pointer on the very top edge still counts
    }

    /// Re-evaluates whether clicks should land on the island or pass through to the windows under the panel.
    func refreshInteractivity() {
        setInteractive?(store.isOpen(on: display) && hitRect.contains(NSEvent.mouseLocation))
    }

    private func clickPassedThrough() {
        guard store.isOpen(on: display), hitRect.contains(NSEvent.mouseLocation) else { return }
        IslandLog.write("anomaly", "click went through the open island (display=\(display), requests=\(store.requests.count)); made it interactive")
        refreshInteractivity()
    }

    private func pointerMoved() {
        guard !store.menuOpen else { return } // the pointer is on the menu, which hangs below the island
        refreshInteractivity()
        let inside = hitRect.contains(NSEvent.mouseLocation)
        let openHere = store.expanded && store.focusDisplay == display
        let noticing = inside && !store.isOpen(on: display)
        if noticing { if store.hoverDisplay != display { store.hoverDisplay = display } }
        else if store.hoverDisplay == display { store.hoverDisplay = nil }
        if !inside && Date() < holdUntil { return }
        if inside == openHere {
            pending?.cancel()
            pending = nil
            return
        }
        guard pending == nil else { return }
        let opening = inside
        pending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(opening ? openDelay : 0.35))
            guard !Task.isCancelled else { return }
            pending = nil
            // The pointer may have moved again while we waited.
            if !opening && Date() < holdUntil { return } // a hold set while we waited wins
            guard hitRect.contains(NSEvent.mouseLocation) == opening, (store.expanded && store.focusDisplay == display) != opening else { return }
            NSLog("iSland: pointer %@ the island", opening ? "entered" : "left")
            IslandLog.write("island", "\(opening ? "open" : "close") display=\(display) sessions=\(store.sessions.count) requests=\(store.requests.count) mode=\(store.mode)")
            if opening { store.focusDisplay = display } // the pointer chooses which display's island is the open one
            store.expanded = opening // the view animates the size change itself
        }
    }
}
