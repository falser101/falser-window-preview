import QtQuick
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: card

  required property var modelData
  required property var controller
  required property int slot
  required property bool selected

  readonly property var wayland: WindowModel.waylandFor(modelData)
  readonly property string title: WindowModel.titleFor(modelData)
  readonly property string appId: WindowModel.appIdFor(modelData)
  readonly property int titleGap: Style.spacing.xs
  readonly property int titleHeight: Style.font.caption + Style.space(4)

  // Selection feedback without a wrapping frame.
  scale: selected ? 1.02 : 1.0
  Behavior on scale {
    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
  }

  function recapture() {
    if (!preview.captureSource)
      return
    preview.captureFrame()
  }

  onWaylandChanged: Qt.callLater(recapture)
  Connections {
    target: card.controller
    function onOpenedChanged() {
      if (card.controller.opened)
        Qt.callLater(card.recapture)
    }
    function onModelRevisionChanged() {
      if (card.controller.opened)
        Qt.callLater(card.recapture)
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: controller.selectAbsolute(card.slot)
    onClicked: function(mouse) {
      if (mouse.button === Qt.MiddleButton)
        controller.requestClose(card.modelData)
      else
        controller.activate(card.modelData)
    }
  }

  Item {
    id: previewHost
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: titleLabel.top
    anchors.bottomMargin: card.titleGap
    clip: true

    Rectangle {
      anchors.fill: parent
      color: "#181818"
      visible: !preview.hasContent
    }

    Text {
      anchors.centerIn: parent
      visible: !preview.hasContent
      text: card.appId || "?"
      color: "#ffffff"
      opacity: 0.55
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
      z: 1
    }

    Item {
      anchors.centerIn: parent
      width: parent.width * 2
      height: parent.height * 2
      scale: 0.5
      layer.enabled: true
      layer.smooth: true

      ScreencopyView {
        id: preview
        anchors.fill: parent
        captureSource: card.wayland
        live: false
        paintCursor: false
        Component.onCompleted: card.recapture()
      }
    }
  }

  Text {
    id: titleLabel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: card.titleHeight
    text: card.title
    color: "#ffffff"
    style: Text.Outline
    styleColor: "#80000000"
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: card.selected
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
