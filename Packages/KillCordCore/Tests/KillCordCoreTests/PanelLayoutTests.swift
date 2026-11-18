@testable import KillCordCore
import Testing

@Suite struct PanelLayoutTests {
    @Test func takesThePreferredHeightWhenTheScreenHasRoom() {
        #expect(PanelLayout.panelHeight(available: 1000, chrome: 260) == PanelLayout.preferredHeight)
        #expect(PanelLayout.panelHeight(available: 800, chrome: 260) == PanelLayout.preferredHeight)
    }

    @Test func shrinksToTheRoomBelowTheMenuBar() {
        #expect(PanelLayout.panelHeight(available: 600, chrome: 260) == 600)
        #expect(PanelLayout.panelHeight(available: 500, chrome: 260) == 500)
    }

    @Test func keepsAMinimumOfCardsBelowTheChrome() {
        #expect(PanelLayout.panelHeight(available: 300, chrome: 260) == 260 + PanelLayout.minimumCardsHeight)
    }

    @Test func availableHeightRunsFromTheButtonToTheBottomOfTheVisibleFrame() {
        // A 700pt visible frame above an 80pt Dock, with the button's bottom at the menu bar's edge.
        #expect(PanelLayout.availableHeight(buttonMinY: 780, visibleMinY: 80) == 700 - PanelLayout.popoverMargin)
        #expect(PanelLayout.availableHeight(buttonMinY: 10, visibleMinY: 80) == 0)
    }
}
