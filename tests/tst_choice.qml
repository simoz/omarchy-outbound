import QtQuick
import QtTest
import qs.Commons
import "../ui" as Outbound

Item {
    width: 320
    height: 240
    Outbound.Choice {
        id: choice
        model: ["All families", "IPv4", "IPv6"]
        description: "Address family"
    }
    TestCase {
        name: "OutboundChoice"
        when: windowShown
        function luminance(color) {
            function linear(value) {
                return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
            }
            return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b);
        }
        function test_dropdown_contrast_data() {
            return [
                {tag: "dark", background: "#061017", foreground: "#c8e5eb"},
                {tag: "light", background: "#f5f2e8", foreground: "#202a30"}
            ];
        }
        function test_dropdown_contrast(data) {
            var background = Color.background;
            var foreground = Color.foreground;
            try {
                Color.background = data.background;
                Color.foreground = data.foreground;
                choice.currentIndex = 0;
                choice.forceActiveFocus();
                keyClick(Qt.Key_Space);
                tryCompare(choice.popup, "opened", true);
                keyClick(Qt.Key_Down);
                compare(choice.highlightedIndex, 1);
                var row = choice.popup.contentItem.itemAtIndex(choice.highlightedIndex);
                verify(row !== null);
                var text = luminance(row.contentItem.color);
                var fill = luminance(row.background.color);
                verify((Math.max(text, fill) + 0.05) / (Math.min(text, fill) + 0.05) >= 4.5,
                       "Highlighted option must have readable contrast");
                keyClick(Qt.Key_Return);
                compare(choice.currentIndex, 1);
                tryCompare(choice.popup, "opened", false);
            } finally {
                choice.popup.close();
                Color.background = background;
                Color.foreground = foreground;
            }
        }
    }
}
