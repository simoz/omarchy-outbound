pragma Singleton
import QtQuick

// QtTest host facade. Real Omarchy bindings are checked separately in preview.
QtObject {
    property color background: "#101519"
    property color foreground: "#d5dfdb"
    property color accent: "#83b6a6"
    property QtObject popups: QtObject {
        property color background: Color.background
        property color text: Color.foreground
    }
}
