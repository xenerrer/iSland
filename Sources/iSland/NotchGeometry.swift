import AppKit

struct NotchGeometry {
    let size: CGSize
    let hasHardwareNotch: Bool

    /// Real notch size on notch displays; a virtual one elsewhere.
    static func current(for screen: NSScreen) -> NotchGeometry {
        let height = screen.safeAreaInsets.top
        if height > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(size: CGSize(width: screen.frame.width - left.width - right.width, height: height),
                                 hasHardwareNotch: true)
        }
        // No notch (an older MacBook, an external display): a virtual one the height of the menu bar, centred at the top.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(size: CGSize(width: 150, height: menuBar >= 20 ? menuBar : 24), hasHardwareNotch: false)
    }
}
