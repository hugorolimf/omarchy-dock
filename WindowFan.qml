import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// The app's windows above its icon: they rise out of the icon as a stack,
// then slide apart into one straight row, each titled underneath
// (AppCell loads it while it is open).
Item {
  required property var dock
  required property Item appCell
  id: fan
  readonly property var app: appCell.app
  readonly property int n: app.windows.length
  readonly property real label: 28
  readonly property real cardW: Math.min(170, dock.screenWidth * 0.9 / Math.max(1, n))
  readonly property real gap: 6
  readonly property real cardH: cardW / 1.6
  readonly property real rowW: n * cardW + (n - 1) * gap
  // Kept on screen: slides sideways when the icon is near an edge.
  readonly property real iconX: appCell.centerX - dock.spacing / 2
  readonly property real shift: Math.max(16 + rowW / 2 - iconX, Math.min(0, dock.screenWidth - 16 - rowW / 2 - iconX))
  readonly property real mid: (n - 1) / 2

  // rise: the stack climbs out of the icon; spread: it opens sideways.
  // Closing runs the same way back. A picked window flies out of the stack
  // into its place on screen (FlyWindow) while the others fold away.
  property real rise: 0
  property real spread: 0
  property int picked: -1
  property bool closing: false
  signal closed()
  function open() {
    closeAnim.stop()
    if (closing) { closing = false; dock.fanClosing-- }
    openAnim.restart()
  }
  function close() {
    if (closing) return
    closing = true
    dock.fanClosing++
    openAnim.stop()
    closeAnim.restart()
  }
  function pickCard(i) {
    if (picked >= 0 || closing) return
    // Only a minimized window flies open: one already on screen just gets
    // focus, one on another workspace gets the workspace slide alone. A
    // minimized one from another workspace waits for that slide first.
    var c = cards.itemAt(i)
    var place = (app.places || [])[i] || ({})
    if (place.minimized && dock.flyWindow && c && c.toplevel) {
      var a = c.mapToItem(null, 5, 5), b = c.mapToItem(null, c.width - 5, c.height - 5)
      var top = (dock.dockScreen ? dock.dockScreen.height : 0) - (dock.dockWindow ? dock.dockWindow.height : 0)
      var fromWs = dock.minimizedFrom()[dock.addr(place.address)]
      var wait = fromWs && fromWs !== dock.currentWs ? 400 : 0
      dock.flyWindow.start(c.toplevel, Qt.rect(a.x, top + a.y, b.x - a.x, b.y - a.y), landing(i), wait)
    } else if (!place.minimized && dock.flyWindow && c && c.toplevel) {
      // In place (here, or after the slide to its workspace): its border lights up.
      dock.flyWindow.lightBorder(place.address, place.ws === dock.currentWs ? 0 : 420)
    }
    picked = i
    var chosenApp = fan.app
    dock.fanKey = ""
    dock.goToWindow(chosenApp, i)
  }
  // Where the window will be, in this screen's coordinates: where it is now,
  // or where a minimized one comes back; else the middle of the screen.
  function landing(i) {
    var r = onScreen(i)
    var scr = dock.dockScreen
    var sw = scr ? scr.width : 1920, sh = scr ? scr.height : 1080
    return r || Qt.rect(sw * 0.2, sh * 0.2, sw * 0.6, sh * 0.6)
  }
  // The window's rect on this dock's screen (a minimized one: where it comes
  // back), or null when it is elsewhere.
  function onScreen(i) {
    var place = (app.places || [])[i] || ({})
    var scr = dock.dockScreen
    var sw = scr ? scr.width : 1920, sh = scr ? scr.height : 1080
    var sx = scr ? scr.x : 0, sy = scr ? scr.y : 0
    var r = null
    if (place.minimized) {
      var m = dock.minimizedRect(place.address)
      var res = dock.monitor && dock.monitor.lastIpcObject ? dock.monitor.lastIpcObject.reserved : null
      if (m) r = Qt.rect(m.x + (res ? res[0] : 0), m.y + (res ? res[1] : 0), m.w, m.h)
    } else {
      var tops = Hyprland.toplevels.values || []
      for (var k = 0; k < tops.length; k++) {
        if (String(tops[k].address) !== String(place.address)) continue
        var ipc = tops[k].lastIpcObject
        if (ipc && ipc.at && ipc.size) r = Qt.rect(ipc.at[0] - sx, ipc.at[1] - sy, ipc.size[0], ipc.size[1])
      }
    }
    if (!r || r.width <= 0 || r.x + r.width <= 0 || r.x >= sw || r.y + r.height <= 0 || r.y >= sh) return null
    return r
  }
  Component.onDestruction: if (closing) dock.fanClosing--
  SequentialAnimation {
    id: openAnim
    running: true
    NumberAnimation { target: fan; property: "rise"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { target: fan; property: "spread"; to: 1; duration: 210; easing.type: Easing.OutBack; easing.overshoot: 0.7 }
  }
  SequentialAnimation {
    id: closeAnim
    NumberAnimation { target: fan; property: "spread"; to: 0; duration: 140; easing.type: Easing.InCubic }
    NumberAnimation { target: fan; property: "rise"; to: 0; duration: 120; easing.type: Easing.InCubic }
    ScriptAction { script: fan.closed() }
  }
  Repeater {
    id: cards
    model: fan.n
    Item {
      id: card
      required property int index
      readonly property var toplevel: fan.app.windows[index]
      readonly property var place: (fan.app.places || [])[index] || ({})
      readonly property bool active: toplevel === ToplevelManager.activeToplevel
      readonly property real c: index - fan.mid
      // The picked one is flying (FlyWindow); the rest fold away.
      visible: fan.picked !== index
      // While stacked, the first window is in front and the others peek
      // out above it, a little smaller, like a pile of cards.
      readonly property real depth: (1 - fan.spread) * index
      width: fan.cardW
      height: fan.cardH
      x: -width / 2 + fan.spread * (c * (fan.cardW + fan.gap) + fan.shift)
      y: -height - fan.label - 10 + (1 - fan.rise) * (height * 0.6 + fan.label) - depth * 7
      z: cardMouse.containsMouse ? fan.n + 1 : fan.n - index
      transformOrigin: Item.Bottom
      // Scale only, no fade: the dock's Liquid Glass is cut by alpha.
      scale: (0.3 + 0.7 * fan.rise) * (1 - depth * 0.04)

      // Same glass as the plate (the fan lives on the dock's layer),
      // so translucent windows like the terminal look as they do.
      Rectangle {
        anchors.fill: parent
        radius: 12
        antialiasing: true
        color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, dock.cfg.opacity)
        border.width: cardMouse.containsMouse ? 2 : 1
        border.color: cardMouse.containsMouse ? Commons.Color.accent
          : Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, card.active ? 0.45 : 0.18)
      }
      Item {
        anchors.fill: parent
        anchors.margins: 5
        opacity: card.place.minimized ? 0.55 : 1
        // Translucent windows (foot is at alpha 0.7) show the
        // wallpaper through their glass on the desktop; without
        // it behind them the thumbnail turns into a black box.
        // Decoded tiny and scaled up smooth = a soft blur.
        Image {
          anchors.fill: cview
          visible: cview.hasContent
          source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
          sourceSize: Qt.size(48, 30)
          fillMode: Image.PreserveAspectCrop
          smooth: true
          cache: false
        }
        ScreencopyView {
          id: cview
          readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height * aspect)
          height: Math.min(parent.height, parent.width / aspect)
          captureSource: card.toplevel || null
          live: true
          paintCursor: false
          constraintSize: Qt.size(width * 2, height * 2)
          visible: hasContent
          layer.enabled: true
          layer.smooth: true
        }
        Image {
          anchors.centerIn: parent
          visible: !cview.hasContent
          width: Math.min(parent.width, parent.height) * 0.5
          height: width
          sourceSize: Qt.size(256, 256)
          source: dock.iconFor(dock.iconCandidates(fan.app.appId), 0)
          smooth: true
          mipmap: true
        }
      }
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 5
        width: Math.min(parent.width * 0.85, ctitle.implicitWidth + 16)
        height: 22
        radius: 11
        antialiasing: true
        color: cardMouse.containsMouse ? Commons.Color.accent
          : Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, Math.max(0.36, dock.cfg.opacity))
        border.width: 1
        border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.16)
        Text {
          id: ctitle
          textFormat: Text.PlainText
          anchors.centerIn: parent
          width: Math.min(implicitWidth, card.width * 0.85 - 16)
          elide: Text.ElideRight
          text: (card.toplevel && card.toplevel.title || fan.app.name) + (card.place.minimized ? dock.tr(" — minimizada") : "")
          color: Commons.Color.menu.text
          font.pixelSize: 12
        }
      }
      MouseArea {
        id: cardMouse
        anchors.fill: parent
        anchors.bottomMargin: -fan.label
        enabled: !fan.closing && fan.picked < 0
        hoverEnabled: true
        onContainsMouseChanged: dock.fanHover(containsMouse)
        onClicked: fan.pickCard(card.index)
      }
    }
  }
}
