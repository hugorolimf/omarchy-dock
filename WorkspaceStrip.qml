import QtQuick
import qs.Commons as Commons

// Workspaces of this monitor: the icons of the apps on each (dimmed:
// minimized from there), loose, with its number on the line of the apps'
// running dots; the current one's number sits in a soft pill that slides. Click to switch, scroll to step; hold one and drag
// it onto another to swap them (2 dropped on 1 becomes the new 1): the tile
// under it slides into the free slot, each showing the number it will have.
// A window dragged over a tile (WindowDrop.qml) makes it open up to take it.
Item {
  id: wsBox
  required property var dock
  visible: dock.showWorkspaces
  anchors.bottom: parent.bottom
  implicitWidth: wsRow.implicitWidth
  implicitHeight: dock.baseSize

  // The tile's parts: icons centred where the apps' icons are, the number
  // centred on the apps' running dots (5 px tall, 2 px off the bottom).
  readonly property int iconSize: Math.round(dock.baseSize * 0.38)
  readonly property int numH: Math.max(9, Math.round(dock.baseSize * 0.2))
  readonly property int topY: Math.round(dock.baseSize * 0.43 - iconSize / 2)
  readonly property int numY: Math.round(dock.baseSize - 4.5 - numH / 2)

  property bool wheelReady: true
  Timer { id: wheelGate; interval: 180; onTriggered: wsBox.wheelReady = true }
  WheelHandler {
    onWheel: function(event) {
      if (!wsBox.wheelReady || event.angleDelta.y === 0) return
      wsBox.wheelReady = false
      wheelGate.restart()
      wsBox.dock.stepWorkspace(event.angleDelta.y < 0 ? 1 : -1)
    }
  }

  // The tile cell of the active workspace; cells set it themselves. A
  // stale one is kept (just hidden) so the highlight slides from there.
  property Item activeCell: null

  // Dragging a tile: the one held, the one under the pointer, and the drop
  // landing (the held tile glides into its new slot; once the swap reaches
  // the dock every tile snaps home showing its new windows).
  property string dragKey: ""
  property string dropKey: ""
  property bool landing: false
  property bool instant: false
  property string landSign: ""

  function cellFor(key) {
    for (var i = 0; i < wsRow.children.length; i++)
      if (wsRow.children[i].key === key) return wsRow.children[i]
    return null
  }
  function keyAt(x) {
    for (var i = 0; i < wsRow.children.length; i++) {
      var c = wsRow.children[i]
      if (c.key !== undefined && x >= c.x && x < c.x + c.width) return c.key
    }
    return ""
  }
  function slotX(key) { var c = cellFor(key); return c ? c.x : 0 }
  function signature(a, b) {
    var wa = dock.wsMap[a], wb = dock.wsMap[b]
    return JSON.stringify([wa ? wa.apps : [], wb ? wb.apps : []])
  }
  function settle() {
    instant = true
    dragKey = ""
    dropKey = ""
    landing = false
    landTimeout.stop()
    Qt.callLater(function() { wsBox.instant = false })
  }
  Connections {
    target: wsBox.dock
    function onWsMapChanged() { if (wsBox.landing && wsBox.signature(wsBox.dragKey, wsBox.dropKey) !== wsBox.landSign) wsBox.settle() }
  }
  // Two workspaces with the same apps look the same swapped: settle anyway.
  Timer { id: landTimeout; interval: 700; onTriggered: wsBox.settle() }

  // Where a workspace's tile is on the screen (WindowDrop needs it).
  function tileRect(id) {
    var c = cellFor(String(id)), w = dock.dockWindow
    if (!c || !w || !dock.dockScreen) return null
    var p = c.mapToItem(null, 0, 0)
    return { x: p.x, y: p.y + dock.dockScreen.height - w.height, w: dock.tileWidth, h: dock.baseSize }
  }
  Component.onCompleted: dock.wsStrip = wsBox

  Rectangle {
    id: wsHighlight
    visible: wsBox.activeCell !== null && wsBox.activeCell.active && wsBox.dragKey === ""
    // Slides toward the active tile, centred on it while it pops in. When
    // workspaces come and go at once the target moves under the slide and
    // it could overshoot past the dock's edge: clamped to the tiles' room.
    property real slideX: wsBox.activeCell ? wsBox.activeCell.x + (wsBox.dock.tileWidth - width) / 2 : 0
    Behavior on slideX { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    x: Math.max(0, Math.min(slideX, wsBox.width - width))
    width: Math.round(wsBox.numH * 2.1) * (wsBox.activeCell ? wsBox.activeCell.pop : 1)
    y: wsBox.numY - 2
    height: wsBox.numH + 4
    scale: width > 0 ? 1 : 0
    radius: height / 2
    antialiasing: true
    color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.16)
  }

  Row {
    id: wsRow
    anchors.bottom: parent.bottom
    leftPadding: wsBox.dock.spacing
    spacing: 0

    Repeater {
      model: wsBox.dock.wsModel
      // Each cell carries its trailing gap, so it animates away with the tile.
      delegate: Item {
        id: wsCell
        required property string key
        readonly property var dock: wsBox.dock
        readonly property var ws: dock.wsMap[key] || ({ id: Number(key), name: key, apps: [], minApps: [] })
        readonly property bool active: Number(key) === dock.currentWs
        // Two steps, so a tile never spills past the plate: the dock first
        // opens room for it (open), then the tile pops in inside that room
        // (pop). Closing runs the other way round, within the ~220 ms the
        // close sweep waits. Set once at creation: tiles there from the
        // start just appear, later ones animate in.
        property real open: 0
        property real pop: 0
        readonly property bool going: dock.wsClosing[key] !== undefined
        SequentialAnimation {
          id: appear
          NumberAnimation { target: wsCell; property: "open"; to: 1; duration: 180; easing.type: Easing.OutCubic }
          NumberAnimation { target: wsCell; property: "pop"; to: 1; duration: 200; easing.type: Easing.OutBack }
        }
        SequentialAnimation {
          id: vanish
          NumberAnimation { target: wsCell; property: "pop"; to: 0; duration: 90; easing.type: Easing.InCubic }
          NumberAnimation { target: wsCell; property: "open"; to: 0; duration: 120; easing.type: Easing.InOutCubic }
        }
        function settle() {
          if (going) { appear.stop(); vanish.start() }
          else { vanish.stop(); if (open < 1 || pop < 1) appear.start() }
        }
        Component.onCompleted: {
          if (!dock.ready && !going) { open = 1; pop = 1 }
          settle()
          if (active) wsBox.activeCell = wsCell
        }
        Component.onDestruction: if (wsBox.activeCell === wsCell) wsBox.activeCell = null
        onGoingChanged: settle()
        onActiveChanged: if (active) wsBox.activeCell = wsCell
        width: (dock.tileWidth + dock.spacing) * open
        height: dock.baseSize

        // Held: follows the pointer (then glides into its new slot). Under
        // the held one: takes the held one's slot, and each shows the number
        // of the slot it is in.
        readonly property bool held: wsBox.dragKey === key
        readonly property bool target: wsBox.dragKey !== "" && !held && wsBox.dropKey === key
        property real dragX: 0
        readonly property real offset: held ? dragX : target ? wsBox.slotX(wsBox.dragKey) - x : 0
        readonly property var slotWs: held && wsBox.dropKey !== "" ? (dock.wsMap[wsBox.dropKey] || ws)
          : target ? (dock.wsMap[wsBox.dragKey] || ws) : ws
        // A window dragged over it (to drop it in), or one just dropped.
        readonly property bool receiving: dock.dropWs === ws.id
        z: held ? 10 : receiving ? 5 : 0

        SequentialAnimation {
          id: bounce
          NumberAnimation { target: tile; property: "landed"; to: 1.22; duration: 120; easing.type: Easing.OutCubic }
          NumberAnimation { target: tile; property: "landed"; to: 1; duration: 320; easing.type: Easing.OutBack }
        }
        Connections {
          target: wsCell.dock
          function onLandedWsChanged() { if (wsCell.dock.landedWs === wsCell.ws.id) bounce.restart() }
        }

        Item {
          id: tile
          readonly property bool active: wsCell.active
          readonly property color ink: Commons.Color.menu.text
          property real landed: 1
          x: wsCell.offset
          Behavior on x {
            enabled: !wsBox.instant && !(wsCell.held && !wsBox.landing)
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
          }
          width: wsCell.dock.tileWidth
          height: wsCell.dock.baseSize
          scale: wsCell.pop * tile.landed * (wsCell.receiving ? 1.16 : wsCell.held ? 1.06 : 1)
          Behavior on scale { enabled: wsCell.pop === 1 && !bounce.running; NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
          opacity: wsCell.pop
          transformOrigin: Item.Bottom
          // Only there when it says something: hover, drag, or a window coming in.
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.round(wsCell.dock.baseSize * 0.2)
            antialiasing: true
            color: wsCell.receiving ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.25)
              : Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, wsCell.held ? 0.12 : tileMouse.containsMouse ? 0.08 : 0)
            border.width: wsCell.receiving || wsCell.target ? 1.5 : 0
            border.color: Commons.Color.accent
            Behavior on color { ColorAnimation { duration: 160 } }
          }
          WsIcons {
            anchors.horizontalCenter: parent.horizontalCenter
            y: wsBox.topY
            dock: wsCell.dock
            ws: wsCell.ws
            size: wsBox.iconSize
            bright: tile.active || tileMouse.containsMouse
          }
          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            y: wsBox.numY
            height: wsBox.numH
            verticalAlignment: Text.AlignVCenter
            text: wsCell.slotWs.name
            color: tile.ink
            opacity: tile.active ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: 160 } }
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: wsBox.numH
            font.weight: tile.active ? Font.DemiBold : Font.Normal
          }

          // Positions in wsRow, so the tile moving under the pointer doesn't
          // feed back into how far it has moved.
          MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            property real pressX: 0
            property bool dragged: false
            onPressed: function(mouse) { pressX = mapToItem(wsRow, mouse.x, 0).x; dragged = false }
            onPositionChanged: function(mouse) {
              if (!pressed || wsBox.landing) return
              var x = mapToItem(wsRow, mouse.x, 0).x
              if (!dragged && Math.abs(x - pressX) > 6) {
                dragged = true
                wsCell.dock.menuIndex = -1
                wsBox.dragKey = wsCell.key
              }
              if (!dragged) return
              wsCell.dragX = x - pressX
              var k = wsBox.keyAt(x)
              wsBox.dropKey = k === wsCell.key ? "" : k
            }
            onReleased: {
              if (!dragged || wsBox.dragKey !== wsCell.key) return
              var to = wsBox.dropKey
              if (to === "") { wsBox.dragKey = ""; wsCell.dragX = 0; return }
              wsBox.landSign = wsBox.signature(wsCell.key, to)
              wsBox.landing = true
              wsCell.dragX = wsBox.slotX(to) - wsCell.x
              landTimeout.restart()
              wsCell.dock.swapWorkspaces(wsCell.ws.id, Number(to))
            }
            onCanceled: if (dragged && !wsBox.landing) { wsBox.dragKey = ""; wsBox.dropKey = ""; wsCell.dragX = 0 }
            onClicked: {
              if (dragged) return
              wsCell.dock.menuIndex = -1
              wsCell.dock.focusWorkspace(wsCell.ws.id)
            }
          }
        }
      }
    }
  }
}
