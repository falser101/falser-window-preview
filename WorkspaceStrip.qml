import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: strip

  required property var controller
  required property var workspaceIds
  required property var allToplevels
  required property int viewWorkspaceId

  readonly property int chipHeight: Style.space(64)
  readonly property int chipWidth: Style.space(104)

  height: chipHeight
  implicitHeight: chipHeight
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    Repeater {
      model: strip.workspaceIds.length

      Rectangle {
        required property int index

        readonly property int workspaceId: strip.workspaceIds[index]
        readonly property bool selected: workspaceId === strip.viewWorkspaceId
        readonly property bool liveFocused: Hyprland.focusedWorkspace
          && Number(Hyprland.focusedWorkspace.id) === workspaceId
        readonly property int windowCount: WindowModel.countOnWorkspace(strip.allToplevels, workspaceId)

        width: strip.chipWidth
        height: strip.chipHeight
        radius: Style.cornerRadius
        color: selected ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.35)
        border.width: selected ? Math.max(2, Style.focusBorderWidth) : 1
        border.color: selected ? Color.accent : Qt.rgba(1, 1, 1, 0.28)
        opacity: windowCount > 0 || selected || liveFocused ? 1 : 0.55

        Column {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: workspaceId === 10 ? "0" : String(workspaceId)
            color: "#ffffff"
            style: Text.Outline
            styleColor: "#80000000"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: selected
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(3)
            visible: windowCount > 0

            Repeater {
              model: Math.min(windowCount, 5)
              Rectangle {
                width: Style.space(6)
                height: Style.space(6)
                radius: width / 2
                color: "#ffffff"
                opacity: 0.85
              }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: strip.controller.selectWorkspace(workspaceId)
        }
      }
    }
  }
}
