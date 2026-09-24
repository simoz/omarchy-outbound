import QtQuick
import qs.Commons

QtObject {
    function fade(color, opacity) { return Qt.rgba(color.r, color.g, color.b, color.a * opacity); }
    // Host tokens are exposed as QtObjects with runtime-defined properties.
    readonly property var popup: Color.popups
    readonly property var typography: Style.font
    readonly property color background: popup.background
    readonly property color text: popup.text
    readonly property color accent: Color.accent
    readonly property color border: fade(text, 0.25)
    readonly property color subdued: fade(text, 0.72)
    readonly property color wash: fade(text, 0.055)
    readonly property string font: typography.family
    readonly property int size: typography.body
}
