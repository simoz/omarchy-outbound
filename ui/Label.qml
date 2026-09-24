import QtQuick

Text {
    id: root
    Theme { id: theme }
    textFormat: Text.PlainText
    color: theme.text
    font.family: theme.font
    font.pixelSize: theme.size
    elide: Text.ElideRight
}
