pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C

Column {
    id: root
    required property var service
    spacing: 6
    Theme { id: theme }
    Label {
        width: parent.width
        text: "02 / DESTINATIONS"
        font.pixelSize: theme.size * 0.8
        color: theme.subdued
    }
    Label {
        width: parent.width
        text: "Illustrative country assignments"
        font.pixelSize: theme.size * 0.8
        color: theme.subdued
    }
    ListView {
        id: list
        width: parent.width
        height: Math.min(224, contentHeight)
        clip: true
        model: root.service.destinations
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        delegate: ActionButton {
            required property var modelData
            required property int index
            width: list.width - 12
            height: 29
            selected: root.service.country === modelData.value
            text: (selected ? "● " : "") + root.service.countryName(modelData.value) + "  / " + modelData.count
            hint: "Filter by " + root.service.countryName(modelData.value)
            onClicked: root.service.chooseCountry(modelData.value)
            onActiveFocusChanged: if (activeFocus) {
                list.currentIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
            }
            Keys.onPressed: function(event) {
                if (event.modifiers !== Qt.NoModifier || (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down)) return;
                var next = Math.max(0, Math.min(list.count - 1, index + (event.key === Qt.Key_Down ? 1 : -1)));
                list.currentIndex = next;
                list.positionViewAtIndex(next, ListView.Contain);
                list.forceLayout();
                list.currentItem.forceActiveFocus();
                event.accepted = true;
            }
        }
    }
}
