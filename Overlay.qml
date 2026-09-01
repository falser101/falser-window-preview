import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginId: String((root.manifest && root.manifest.id) || "io.github.falser101.window-preview")
  readonly property var pluginEntry: {
    var config = root.shell && root.shell.shellConfig ? root.shell.shellConfig : null
    var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
    for (var i = 0; i < plugins.length; i++) {
      if (plugins[i] && String(plugins[i].id || "") === root.pluginId)
        return plugins[i]
    }
    return null
  }

  // Hot corner config (persisted on the plugin entry in shell.json).
  // Always on — user only chooses top-left vs top-right.
  readonly property bool hotCornerEnabled: true
  readonly property string hotCornerPosition: {
    var position = String((root.pluginEntry && root.pluginEntry.hotCornerPosition) || "top-left")
    return (position === "top-right") ? "top-right" : "top-left"
  }
  readonly property bool hotCornerOnTop: true
  readonly property bool hotCornerOnLeft: root.hotCornerPosition === "top-left"
  readonly property int hotCornerReach: Style.space(48)
  readonly property int hotCornerDepth: Style.space(6)
  property bool hotCornerArmed: true

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property int viewWorkspaceId: 1
  property int modelRevision: 0
  // "windows" = navigate the preview grid; "workspaces" = navigate the strip
  property string focusPane: "windows"

  readonly property var allToplevels: Hyprland.toplevels ? Hyprland.toplevels.values : []
  readonly property var allWorkspaces: Hyprland.workspaces ? Hyprland.workspaces.values : []
  readonly property var workspaceIds: {
    var _ = root.modelRevision
    return WindowModel.workspaceIds(root.allWorkspaces, 5)
  }
  readonly property var filteredToplevels: {
    var _ = root.modelRevision
    return WindowModel.collect(root.allToplevels, root.filterText, root.viewWorkspaceId)
  }
  readonly property var viewWorkspace: WindowModel.workspaceById(root.allWorkspaces, root.viewWorkspaceId)

  readonly property string wallpaperPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  readonly property color foreground: "#f2f2f2"
  readonly property color border: Qt.rgba(1, 1, 1, 0.22)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(28), Style.font.subtitle + Style.spacing.controlPaddingY)
  readonly property int footerHeight: Style.space(40)
  readonly property int stripHeight: Style.space(72)
  readonly property int contentSpacing: Style.spacing.md
  readonly property int outerMargin: Math.max(Style.gapsOut, Style.space(24))
  readonly property real wallpaperDim: 0.40
  readonly property int gridWidth: Math.max(1, panel.width - outerMargin * 2)
  readonly property int gridHeight: Math.max(1, panel.height - outerMargin * 2 - stripHeight - headerHeight - footerHeight - contentSpacing * 4)
  readonly property var windowLayout: {
    var _ = root.modelRevision
    return WindowModel.buildLayout(
      root.filteredToplevels,
      root.viewWorkspace,
      root.gridWidth,
      root.gridHeight,
      Style.spacing.lg
    )
  }
  readonly property var layoutSlots: root.windowLayout.slots || []
  readonly property int columns: Math.max(1, Number(root.windowLayout.columns) || 1)

  function updatePluginSetting(name, value) {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function")
      return
    var settings = {}
    var current = root.pluginEntry || {}
    for (var key in current) {
      if (key !== "id")
        settings[key] = current[key]
    }
    settings[name] = value
    root.shell.updateEntryInline(root.pluginId, settings)
  }

  function setHotCornerPosition(value) {
    var position = value === "top-right" ? "top-right" : "top-left"
    if (position !== root.hotCornerPosition)
      root.updatePluginSetting("hotCornerPosition", position)
  }

  function hotCornerHovered() {
    for (var i = 0; i < hotCornerInstances.instances.length; i++) {
      var win = hotCornerInstances.instances[i]
      if (win && win.hotCornerHovered)
        return true
    }
    return false
  }

  function triggerHotCorner(screenName) {
    if (!root.hotCornerEnabled || !root.hotCornerArmed)
      return
    root.hotCornerArmed = false
    if (root.opened) {
      root.dismiss()
      return
    }
    root.open("{}")
  }

  function scheduleHotCornerRearm() {
    hotCornerRearm.restart()
  }

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.focusPane = "windows"
    root.viewWorkspaceId = Hyprland.focusedWorkspace
      ? Number(Hyprland.focusedWorkspace.id)
      : 1
    if (root.viewWorkspaceId <= 0)
      root.viewWorkspaceId = 1
    root.modelRevision++
    root.selectedIndex = root.slotIndexForToplevel(Hyprland.activeToplevel)
    Qt.callLater(function() {
      root.modelRevision++
      root.selectedIndex = root.slotIndexForToplevel(Hyprland.activeToplevel)
      keyCatcher.forceActiveFocus()
    })
  }

  function slotIndexForToplevel(toplevel) {
    if (!toplevel)
      return 0
    for (var i = 0; i < root.layoutSlots.length; i++) {
      if (root.layoutSlots[i] && root.layoutSlots[i].top === toplevel)
        return i
    }
    return 0
  }

  function close() {
    root.opened = false
    root.scheduleHotCornerRearm()
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    root.scheduleHotCornerRearm()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.focusPane = "windows"
    root.selectedIndex = 0
    root.modelRevision++
  }

  function selectAbsolute(index) {
    root.focusPane = "windows"
    if (root.layoutSlots.length === 0) {
      root.selectedIndex = 0
      return
    }
    root.selectedIndex = Math.max(0, Math.min(index, root.layoutSlots.length - 1))
    root.ensureSlotVisible(root.selectedIndex)
  }

  function select(delta) {
    root.focusPane = "windows"
    if (root.layoutSlots.length === 0) return
    var next = root.selectedIndex + delta
    if (next < 0) next = root.layoutSlots.length - 1
    if (next >= root.layoutSlots.length) next = 0
    root.selectedIndex = next
    root.ensureSlotVisible(root.selectedIndex)
  }

  function selectRow(delta) {
    select(delta * root.columns)
  }

  function ensureSlotVisible(index) {
    // Responsive grid always fits on one screen — nothing to scroll.
  }

  function selectWorkspace(workspaceId) {
    var id = Number(workspaceId)
    if (!isFinite(id) || id <= 0)
      return

    root.viewWorkspaceId = id
    root.focusPane = "workspaces"
    root.filterText = ""
    root.selectedIndex = 0
    root.modelRevision++

    var workspace = WindowModel.workspaceById(root.allWorkspaces, id)
    if (workspace && typeof workspace.activate === "function")
      workspace.activate()
    else
      Hyprland.dispatch('hl.dsp.focus({ workspace = "' + id + '" })')

    Qt.callLater(function() {
      root.selectedIndex = root.slotIndexForToplevel(Hyprland.activeToplevel)
      keyCatcher.forceActiveFocus()
    })
  }

  function shiftWorkspace(delta) {
    var ids = root.workspaceIds
    if (!ids.length) return
    var current = ids.indexOf(root.viewWorkspaceId)
    if (current < 0) current = 0
    var next = (current + delta + ids.length) % ids.length
    root.selectWorkspace(ids[next])
  }

  function activate(top) {
    var wayland = WindowModel.waylandFor(top)
    if (!wayland || typeof wayland.activate !== "function")
      return
    wayland.activate()
    root.dismiss()
  }

  function activateSelected() {
    if (root.focusPane === "workspaces") {
      root.focusPane = "windows"
      if (root.layoutSlots.length === 0)
        root.dismiss()
      return
    }
    if (root.layoutSlots.length === 0) {
      root.dismiss()
      return
    }
    var slot = root.layoutSlots[root.selectedIndex]
    if (slot && slot.top)
      root.activate(slot.top)
  }

  function requestClose(top) {
    var wayland = WindowModel.waylandFor(top)
    if (!wayland || typeof wayland.close !== "function")
      return
    wayland.close()
  }

  function refreshSelectionBounds() {
    if (root.selectedIndex >= root.layoutSlots.length)
      root.selectedIndex = Math.max(0, root.layoutSlots.length - 1)
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (!root.opened) return
      root.modelRevision++
      root.refreshSelectionBounds()
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() {
      if (!root.opened) return
      root.modelRevision++
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      if (!root.opened) return
      if (Hyprland.focusedWorkspace) {
        var id = Number(Hyprland.focusedWorkspace.id)
        if (id > 0 && id !== root.viewWorkspaceId) {
          root.viewWorkspaceId = id
          root.selectedIndex = 0
          root.modelRevision++
        }
      }
    }
  }

  Timer {
    id: hotCornerRearm
    interval: 450
    repeat: false
    onTriggered: {
      if (!root.hotCornerHovered())
        root.hotCornerArmed = true
    }
  }

  component HotCornerTarget: Item {
    id: cornerTarget
    required property bool onTop
    required property bool onLeft
    readonly property bool hovered: horizontalTarget.containsMouse || verticalTarget.containsMouse
    signal entered()
    signal exited()

    implicitWidth: root.hotCornerReach
    implicitHeight: root.hotCornerReach

    MouseArea {
      id: horizontalTarget
      x: 0
      y: cornerTarget.onTop ? 0 : parent.height - height
      width: parent.width
      height: root.hotCornerDepth
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: cornerTarget.entered()
      onExited: cornerTarget.exited()
    }

    MouseArea {
      id: verticalTarget
      x: cornerTarget.onLeft ? 0 : parent.width - width
      y: 0
      width: root.hotCornerDepth
      height: parent.height
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: cornerTarget.entered()
      onExited: cornerTarget.exited()
    }
  }

  // Invisible L-shaped hit targets on each screen while overview is closed.
  Variants {
    id: hotCornerInstances
    model: root.hotCornerEnabled && !root.opened ? Quickshell.screens : []

    PanelWindow {
      required property var modelData
      screen: modelData
      visible: true
      anchors {
        top: root.hotCornerOnTop
        right: !root.hotCornerOnLeft
        bottom: !root.hotCornerOnTop
        left: root.hotCornerOnLeft
      }
      implicitWidth: root.hotCornerReach
      implicitHeight: root.hotCornerReach
      color: "#02000000"
      mask: Region {
        Region {
          x: 0
          y: root.hotCornerOnTop ? 0 : root.hotCornerReach - root.hotCornerDepth
          width: root.hotCornerReach
          height: root.hotCornerDepth
        }
        Region {
          x: root.hotCornerOnLeft ? 0 : root.hotCornerReach - root.hotCornerDepth
          y: 0
          width: root.hotCornerDepth
          height: root.hotCornerReach
        }
      }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "falser-window-preview-hot-corner"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.exclusiveZone: -1
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      readonly property bool hotCornerHovered: closedHotCorner.hovered

      HotCornerTarget {
        id: closedHotCorner
        anchors.fill: parent
        onTop: root.hotCornerOnTop
        onLeft: root.hotCornerOnLeft
        onEntered: root.triggerHotCorner(String(modelData.name || ""))
        onExited: root.scheduleHotCornerRearm()
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#0b0b0b"
    WlrLayershell.namespace: "falser-window-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Image {
      id: wallpaper
      anchors.fill: parent
      source: Util.fileUrl(root.wallpaperPath)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      mirror: false
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, root.wallpaperDim)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      z: 20

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.filterText) root.setFilter("")
          else root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab && !(event.modifiers & Qt.ControlModifier)) {
          root.shiftWorkspace(event.modifiers & Qt.ShiftModifier ? -1 : 1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.shiftWorkspace(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.shiftWorkspace(1)
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Left) {
          root.shiftWorkspace(-1)
          event.accepted = true
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Right) {
          root.shiftWorkspace(1)
          event.accepted = true
        } else if (!root.filterText && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && event.text && /^[1-9]$/.test(event.text)) {
          root.selectWorkspace(Number(event.text))
          event.accepted = true
        } else if (!root.filterText && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                   && event.text === "0") {
          root.selectWorkspace(10)
          event.accepted = true
        } else if (Util.editsFilter(event, root.filterText)) {
          root.setFilter(Util.editedFilter(event, root.filterText))
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          if (root.focusPane === "workspaces")
            root.shiftWorkspace(-1)
          else
            root.select(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          if (root.focusPane === "workspaces")
            root.shiftWorkspace(1)
          else
            root.select(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          if (root.focusPane === "windows" && root.selectedIndex < root.columns)
            root.focusPane = "workspaces"
          else if (root.focusPane === "windows")
            root.selectRow(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          if (root.focusPane === "workspaces") {
            root.focusPane = "windows"
            if (root.filteredToplevels.length > 0)
              root.selectedIndex = Math.min(root.selectedIndex, root.filteredToplevels.length - 1)
          } else {
            root.selectRow(1)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Q && (event.modifiers & Qt.ShiftModifier)) {
          if (!event.isAutoRepeat && root.layoutSlots.length > 0) {
            var closeSlot = root.layoutSlots[root.selectedIndex]
            if (closeSlot && closeSlot.top)
              root.requestClose(closeSlot.top)
          }
          event.accepted = true
        } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
          root.setFilter(root.filterText + event.text)
          event.accepted = true
        }
      }
    }

    Column {
      id: layout
      anchors.fill: parent
      anchors.margins: root.outerMargin
      spacing: root.contentSpacing

      WorkspaceStrip {
        width: parent.width
        controller: root
        workspaceIds: root.workspaceIds
        allToplevels: root.allToplevels
        viewWorkspaceId: root.viewWorkspaceId
      }

      Item {
        width: parent.width
        height: root.headerHeight

        MouseArea { anchors.fill: parent; onClicked: {} }

        Text {
          anchors.fill: parent
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: root.filterText
            ? ("Search on workspace " + root.viewWorkspaceId + ": " + root.filterText)
            : ("Workspace " + root.viewWorkspaceId
               + "  ·  Tab / PgUp·PgDn switch  ·  ←→↑↓ windows  ·  Enter activate  ·  Esc")
          color: root.foreground
          style: Text.Outline
          styleColor: "#90000000"
          opacity: root.filterText ? 1 : 0.85
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          elide: Text.ElideRight
        }
      }

      Item {
        width: parent.width
        height: parent.height - root.stripHeight - root.headerHeight - root.footerHeight - root.contentSpacing * 3

        MouseArea { anchors.fill: parent; onClicked: {} }

        Text {
          anchors.centerIn: parent
          visible: root.layoutSlots.length === 0
          text: root.filterText
            ? "No matching windows on this workspace"
            : "No windows on this workspace"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        Item {
          id: layoutCanvas
          anchors.fill: parent
          visible: root.layoutSlots.length > 0
          clip: true

          Repeater {
            model: root.layoutSlots.length

            WindowCard {
              required property int index

              readonly property var slotData: root.layoutSlots[index] || null

              x: slotData ? slotData.x : 0
              y: slotData ? slotData.y : 0
              width: slotData ? slotData.w : 0
              height: slotData ? slotData.h : 0
              modelData: slotData ? slotData.top : null
              controller: root
              slot: index
              selected: root.focusPane === "windows" && index === root.selectedIndex
              visible: slotData && slotData.top
            }
          }
        }
      }

      // Hot-corner settings footer
      Item {
        width: parent.width
        height: root.footerHeight

        MouseArea { anchors.fill: parent; onClicked: {} }

        Row {
          id: footer
          anchors.centerIn: parent
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Hot corner"
            color: root.foreground
            style: Text.Outline
            styleColor: "#90000000"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            opacity: 0.8
          }

          Repeater {
            model: [
              { id: "top-left", label: "Top-left" },
              { id: "top-right", label: "Top-right" }
            ]

            Rectangle {
              required property var modelData

              readonly property bool active: root.hotCornerPosition === modelData.id

              width: chipLabel.implicitWidth + Style.space(20)
              height: Style.space(30)
              radius: height / 2
              color: active ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.35)
              border.width: active ? Math.max(2, Style.focusBorderWidth) : 1
              border.color: active ? Color.accent : Qt.rgba(1, 1, 1, 0.28)

              Text {
                id: chipLabel
                anchors.centerIn: parent
                text: modelData.label
                color: "#ffffff"
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: parent.active
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setHotCornerPosition(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
