import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// A window dragged onto one of this dock's workspace tiles goes to that
// workspace. The windowing script (dockdrop.lua) follows the drag and writes
// <stateDir>/drag ("seq phase address ws cx cy fx fy fw fh"); the dock shows
// itself when a drag starts and lists where its tiles are (tiles-<monitor>,
// "id x y w h" in global px). Over a tile, the window (faded out by the
// script) is drawn here leaving its spot and hanging over the tile, small,
// as if already on its way in; let go and it sinks into the tile, which
// bounces. Without the script nothing here ever starts.
Item {
  id: drop
  required property var dock

  property real seq: -1
  property string address: ""
  property var from: ({ x: 0, y: 0, w: 1, h: 1 })   // the window, screen-local
  property var tile: ({ x: 0, y: 0, w: 1, h: 1 })   // the tile, screen-local
  property bool shown: false
  readonly property real aspect: from.h > 0 ? from.w / from.h : 1.6
  // Hanging over the tile: a small card of the window, just above it.
  readonly property real cardW: Math.max(tile.w * 2.2, 120)
  readonly property var card: ({ x: tile.x + tile.w / 2 - cardW / 2, y: tile.y - cardW / aspect - 12, w: cardW, h: cardW / aspect })
  readonly property var toplevel: {
    var list = Hyprland.toplevels.values || []
    var a = address.replace(/^0x/, "")
    for (var i = 0; i < list.length; i++)
      if (String(list[i].address || "").replace(/^0x/, "") === a) return list[i].wayland
    return null
  }

  FileView {
    id: dragFile
    path: drop.dock.stateDir + "/drag"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: drop.read()
  }

  function local(x, y, w, h) {
    var s = dock.dockScreen
    return { x: x - (s ? s.x : 0), y: y - (s ? s.y : 0), w: w, h: h }
  }

  function read() {
    var f = String(dragFile.text() || "").trim().split(" ")
    if (f.length < 10 || Number(f[0]) === seq) return
    var first = seq < 0
    seq = Number(f[0])
    if (first) return   // left over from before the shell started
    var phase = f[1], ws = Number(f[3])
    var mine = phase !== "hover" && phase !== "drop" || (dock.wsMap[String(ws)] !== undefined && !!dock.wsStrip)
    if (phase === "start") dock.windowDragging = true
    else if (phase === "end") finish()
    else if (phase === "leave" || !mine) leave()
    else if (phase === "hover") {
      var t = dock.wsStrip.tileRect(ws)
      if (!t) { leave(); return }
      address = f[2]
      from = local(Number(f[6]), Number(f[7]), Math.max(1, Number(f[8])), Math.max(1, Number(f[9])))
      tile = t
      dock.dropWs = ws
      intoTile.stop(); away.stop()
      ghost.gx = from.x; ghost.gy = from.y; ghost.gw = from.w; ghost.gh = from.h
      ghost.opacity = 1
      shown = true
      toCard.restart()
    } else if (phase === "drop") {
      dock.dropWs = -1
      toCard.stop(); bob.stop()
      intoTile.restart()
      landed.ws = ws
      landed.restart()
    }
  }

  function leave() {
    dock.dropWs = -1
    toCard.stop(); bob.stop()
    if (shown) away.restart()
  }
  function finish() {
    leave()
    dock.windowDragging = false
  }

  // The tile bounces as the window lands in it, a moment after the drop.
  Timer {
    id: landed
    property int ws: -1
    interval: 200
    onTriggered: { drop.dock.landedWs = ws; landedReset.restart(); drop.dock.windowDragging = false }
  }
  Timer { id: landedReset; interval: 500; onTriggered: drop.dock.landedWs = -1 }

  // Tile places, again and again while the dock slides in and grows (a
  // few lines in a small file).
  Timer {
    interval: 120
    repeat: true
    triggeredOnStart: true
    running: drop.dock.windowDragging
    onTriggered: drop.publish()
  }
  function publish() {
    var s = dock.dockScreen
    if (!s || !dock.wsStrip || dock.monitorName === "") return
    var lines = []
    for (var i = 0; i < dock.workspaceList.length; i++) {
      var id = dock.workspaceList[i].id, r = dock.wsStrip.tileRect(id)
      if (r) lines.push([id, Math.round(r.x + s.x), Math.round(r.y + s.y), Math.round(r.w), Math.round(r.h)].join(" "))
    }
    tilesFile.setText(lines.join("\n") + "\n")
  }
  FileView {
    id: tilesFile
    path: drop.dock.monitorName !== "" ? drop.dock.stateDir + "/tiles-" + drop.dock.monitorName : ""
  }

  PanelWindow {
    screen: drop.dock.dockScreen
    visible: drop.shown
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock-drop"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Item {
      id: ghost
      property real gx: 0
      property real gy: 0
      property real gw: 1
      property real gh: 1
      property real sink: 0
      x: gx
      y: gy + sink
      width: gw
      height: gh

      Rectangle {
        anchors.fill: parent
        radius: Math.min(14, ghost.width * 0.08)
        color: Commons.Color.menu.background
        border.width: 1
        border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
        clip: true
        // Translucent windows (the terminal) show the wallpaper, as on the desktop.
        Image {
          anchors.fill: parent
          source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
          sourceSize: Qt.size(48, 30)
          fillMode: Image.PreserveAspectCrop
          smooth: true
          cache: false
        }
        ScreencopyView {
          anchors.fill: parent
          captureSource: drop.shown ? drop.toplevel : null
          live: true
          paintCursor: false
          constraintSize: Qt.size(Math.max(1, drop.from.w), Math.max(1, drop.from.h))
        }
      }
    }

    // Out of its spot and over the tile, then a slow sway down toward it.
    ParallelAnimation {
      id: toCard
      NumberAnimation { target: ghost; property: "gx"; to: drop.card.x; duration: 300; easing.type: Easing.OutCubic }
      NumberAnimation { target: ghost; property: "gy"; to: drop.card.y; duration: 300; easing.type: Easing.OutCubic }
      NumberAnimation { target: ghost; property: "gw"; to: drop.card.w; duration: 300; easing.type: Easing.OutCubic }
      NumberAnimation { target: ghost; property: "gh"; to: drop.card.h; duration: 300; easing.type: Easing.OutCubic }
      onFinished: bob.restart()
    }
    SequentialAnimation {
      id: bob
      loops: Animation.Infinite
      NumberAnimation { target: ghost; property: "sink"; to: 6; duration: 520; easing.type: Easing.InOutSine }
      NumberAnimation { target: ghost; property: "sink"; to: 0; duration: 520; easing.type: Easing.InOutSine }
    }
    // Let go: down into the tile, shrinking to it and fading at the end.
    ParallelAnimation {
      id: intoTile
      NumberAnimation { target: ghost; property: "gx"; to: drop.tile.x + drop.tile.w * 0.2; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: ghost; property: "gy"; to: drop.tile.y + drop.tile.h * 0.2; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: ghost; property: "gw"; to: drop.tile.w * 0.6; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: ghost; property: "gh"; to: drop.tile.h * 0.6; duration: 240; easing.type: Easing.InCubic }
      NumberAnimation { target: ghost; property: "sink"; to: 0; duration: 240 }
      SequentialAnimation {
        PauseAnimation { duration: 140 }
        NumberAnimation { target: ghost; property: "opacity"; to: 0; duration: 100 }
      }
      onFinished: drop.shown = false
    }
    // Pulled away from the tile: the window shows again where it is.
    NumberAnimation {
      id: away
      target: ghost; property: "opacity"; to: 0; duration: 140
      onFinished: drop.shown = false
    }
  }
}
