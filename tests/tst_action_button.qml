import QtQuick
import QtTest
import "../ui" as Outbound

Item {
    width: 200
    height: 100
    Outbound.ActionButton { id: button; flat: true; text: "⚙"; hint: "Settings" }
    Item { id: other; focus: true }
    TestCase {
        name: "OutboundActionButton"
        when: windowShown
        function test_mouse_focus_is_not_outlined_but_keyboard_focus_is() {
            mouseClick(button);
            verify(button.activeFocus);
            compare(button.background.border.width, 1);
            other.forceActiveFocus();
            button.forceActiveFocus(Qt.TabFocusReason);
            compare(button.background.border.width, 2);
        }
    }
}
