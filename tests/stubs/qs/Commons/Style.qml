pragma Singleton
import QtQuick

QtObject {
    property QtObject font: QtObject {
        property string family: "monospace"
        property int body: 13
    }
}
