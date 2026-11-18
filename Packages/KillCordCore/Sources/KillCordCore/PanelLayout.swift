import Foundation

/// Sizes the panel so it fits below the menu bar on the status item's screen: the connection cards scroll, and
/// the fascia and footer stay in view.
public enum PanelLayout {
    /// The panel's height when the screen has room for it.
    public static let preferredHeight: Double = 640
    /// The shortest the cards area gets, however little room the screen has.
    public static let minimumCardsHeight: Double = 120
    /// Room kept free below the status item for the popover's arrow and a gap above the Dock or screen edge.
    public static let popoverMargin: Double = 28

    /// The height a popover can use below a status item: from the bottom of its button down to the bottom of the
    /// screen's visible frame (above the Dock), less the arrow and a gap. Both values are in screen coordinates.
    public static func availableHeight(buttonMinY: Double, visibleMinY: Double) -> Double {
        max(0, buttonMinY - visibleMinY - popoverMargin)
    }

    /// The panel's height: the preferred height, or the room `available` when that's less, but always enough
    /// for the parts outside the scroll area (`chrome`) plus `minimumCardsHeight` of cards.
    public static func panelHeight(available: Double, chrome: Double) -> Double {
        max(min(preferredHeight, available), chrome + minimumCardsHeight)
    }
}
