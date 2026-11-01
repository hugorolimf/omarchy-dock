import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// One app in the dock's strip (DockWindow's Repeater): its icon with the
// hover zoom, launch bounce, running dots, workspace badge, name, menu and
// window fan; click, middle click, right click and drag to reorder.
Item {
  id: cell
  required property var dock
  required property string key
  required property int index
  readonly property bool dragging: dock.dragKey === key
  z: dragging || dock.fanKey === key ? 5 : 0
  readonly property var app: dock.itemMap[key] || ({ id: key, appId: key, name: key, pinned: false, windows: [] })
  // From the resting layout, like macOS: using the live x/width
  // made zoom depend on itself (binding loop, wasted CPU).
  readonly property real centerX: dock.restStripLeft + index * dock.slot + dock.slot / 2
  readonly property real dist: Math.abs(dock.hoverX - centerX)
  readonly property real zoom: dock.hovering && dock.hoverX > -500
    ? 1 + (dock.maxScale - 1) * Math.exp(-(dist * dist) / (2 * Math.pow(dock.baseSize * 1.15, 2))) : 1
  // 0..1: grows in when added (app opened), shrinks away when
  // (un)pinned or when its last window closes.
  property real grow: dock.ready ? 0 : 1
  readonly property bool going: dock.leavingKey === key || dock.closing[key] !== undefined
  Component.onCompleted: grow = going ? 0 : 1
  onGoingChanged: grow = going ? 0 : 1
  // Grows in unhurried; shrinking stays quick (pinTimer and closeSweep wait on it).
  Behavior on grow { NumberAnimation { duration: cell.going ? 180 : 360; easing.type: cell.going ? Easing.OutCubic : Easing.OutBack } }

  // Launch bounce: a smooth, continuous up-and-down (no rest between
  // hops) until the new window appears. Then it stops right where it
  // is and the icon glides down from that height (no extra hop).
  readonly property bool bouncing: dock.launching[key] !== undefined
  readonly property real bounceHeight: dock.baseSize * 0.4
  property real lift: 0
  onBouncingChanged: if (!bouncing && lift > 0) settle.restart()
  SequentialAnimation {
    running: cell.bouncing
    loops: Animation.Infinite
    NumberAnimation { target: cell; property: "lift"; to: cell.bounceHeight; duration: 480; easing.type: Easing.InOutSine }
    NumberAnimation { target: cell; property: "lift"; to: 0; duration: 480; easing.type: Easing.InOutSine }
  }
  NumberAnimation {
    id: settle
    target: cell; property: "lift"; to: 0
    // Shorter from lower down, so the speed stays even.
    duration: 160 + 260 * Math.min(1, cell.lift / cell.bounceHeight)
    easing.type: Easing.OutCubic
  }

  // Pulled off the dock (or just dropped there): its gap closes.
  readonly property bool poofing: dock.poofKey === key
  readonly property bool lifted: (dragging && dock.dragRemoves) || poofing
  property real poof: poofing ? 0 : 1
  Behavior on poof { NumberAnimation { duration: 180; easing.type: Easing.InCubic } }

  width: (dock.baseSize * zoom + dock.spacing) * grow * (lifted ? 0 : 1)
  height: dock.baseSize * zoom
  anchors.bottom: parent.bottom
  Behavior on width { enabled: cell.grow === 1; NumberAnimation { duration: 70 } }
  Behavior on height { NumberAnimation { duration: 70 } }

  // Click feedback: the icon sinks while pressed and springs back on
  // release; a quick tap plays the whole press.
  property real press: 1
  NumberAnimation { id: pressDown; target: cell; property: "press"; to: 0.84; duration: 80; easing.type: Easing.OutQuad }
  NumberAnimation { id: pressUp; target: cell; property: "press"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
  SequentialAnimation {
    id: pressTap
    NumberAnimation { target: cell; property: "press"; to: 0.84; duration: 70; easing.type: Easing.OutQuad }
    NumberAnimation { target: cell; property: "press"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
  }
  function pressStart() { pressUp.stop(); pressTap.stop(); pressDown.restart() }
  function pressEnd() {
    pressDown.stop()
    if (press > 0.9) pressTap.restart()
    else pressUp.restart()
  }

  // The icon is drawn a bit smaller than its slot and raised, so the
  // running dot sits inside the slot under it (the plate keeps its size).
  Image {
    // Centred on the icon's own room: the slot also carries the gap
    // to the next icon on its right.
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: -dock.spacing * cell.grow / 2
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(dock.baseSize * cell.zoom * 0.17)
    width: dock.baseSize * cell.zoom * 0.80
    height: width
    scale: cell.grow * cell.poof * cell.press
    opacity: cell.grow * (cell.lifted ? 0.6 : 1)
    transformOrigin: cell.poofing ? Item.Center : Item.Bottom
    // Follows the pointer while dragged (upwards too, to pull it
    // off), then glides into its slot. After a removal it jumps
    // home unseen instead (poof is still 0 at that moment).
    transform: Translate {
      id: shift
      readonly property bool held: cell.dragging || cell.poofing
      readonly property bool glide: !held && cell.poof === 1
      x: held ? dock.dragX - (cell.x + cell.width / 2) : 0
      y: held ? Math.min(0, dock.dragY - (cell.y + cell.height / 2)) : -cell.lift
      Behavior on x { enabled: shift.glide; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on y { enabled: shift.glide && !cell.bouncing && !settle.running; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    // dock.tr("Remover") above the icon while dropping it would unpin it.
    Rectangle {
      visible: cell.dragging && dock.dragRemoves
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.top
      anchors.bottomMargin: 6
      width: removeLabel.implicitWidth + 16
      height: removeLabel.implicitHeight + 8
      radius: 8
      color: Commons.Color.menu.background
      border.width: 1
      border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.2)
      Text {
        id: removeLabel
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: dock.tr("Remover")
        color: Commons.Color.menu.text
        font.pixelSize: 13
      }
    }
    property var iconList: dock.iconCandidates(cell.app.appId)
    property int iconTry: 0
    onIconListChanged: iconTry = 0
    source: dock.iconFor(iconList, iconTry)
    onStatusChanged: if (status === Image.Error) Qt.callLater(() => iconTry++)
    // Rasterised well above the shown size and scaled down with
    // mipmaps: plain smoothing left round icons (Spotify) jagged.
    sourceSize: Qt.size(256, 256)
    smooth: true
    mipmap: true
    fillMode: Image.PreserveAspectFit
  }

  // Running indicator: one dot per window (up to 3), so two
  // terminals don't read as one.
  Row {
    id: dots
    // Dim dot: running in the background with no window (closed
    // with Super + W); Super + Q or the menu quits it.
    readonly property bool background: !!cell.app.background
    readonly property bool on: cell.app.windows.length > 0 || background
    readonly property int active: on && !background ? dock.activeWindow(cell.app) : -1
    spacing: 3
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: -dock.spacing * cell.grow / 2
    anchors.bottom: parent.bottom
    // ~5 px clear of the icon above, inside the slot
    anchors.bottomMargin: 2
    Repeater {
      model: Math.max(1, Math.min(3, cell.app.windows.length))
      Rectangle {
        required property int index
        // Hollow dot: this window is minimized.
        readonly property bool minimized: !dots.background && !!((cell.app.places || [])[index] || {}).minimized
        // The window in focus gets a short pill instead of a dot, so
        // the active one reads at a glance (the third dot stands for
        // any window past it).
        readonly property bool focused: dots.active >= 0 && Math.min(dots.active, 2) === index
        border.width: minimized ? 1 : 0
        border.color: Commons.Color.menu.text
        opacity: dots.on ? (dots.background ? 0.35 : focused ? 1 : 0.75) : 0
        scale: dots.on ? 1 : 0.2
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] } }
        Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
        width: focused ? 14 : 5
        height: 5
        radius: 2.5
        Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.Bezier; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] } }
        color: minimized ? "transparent" : Commons.Color.menu.text
      }
    }
  }

  // Workspace badge: where the app's windows are, shown once any of
  // them sits outside the current workspace.
  Rectangle {
    // Other workspaces only (the current one is implied); at most two, then "+N".
    readonly property var others: (cell.app.workspaces || []).filter(function(w) { return w !== dock.currentWs }).map(dock.wsLabel)
    readonly property string label: others.length <= 2 ? others.join("·")
      : others.slice(0, 2).join("·") + "+" + (others.length - 2)
    visible: dock.cfg.workspaceBadges && cell.grow === 1 && others.length > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.rightMargin: dock.spacing / 2 - 3
    anchors.topMargin: -3
    width: Math.max(height, badgeText.implicitWidth + 8)
    height: Math.max(14, Math.round(dock.baseSize * 0.32))
    radius: height / 2
    color: Commons.Color.accent
    Text {
      id: badgeText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: parent.label
      color: Commons.Color.menu.background
      font.pixelSize: Math.max(9, Math.round(parent.height * 0.62))
      font.bold: true
    }
  }

  // Name tooltip.
  Rectangle {
    visible: tip.hovered && dock.menuIndex < 0 && dock.fanKey !== cell.key && dock.dragKey === ""
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.top
    anchors.bottomMargin: 8
    width: label.implicitWidth + 16
    height: label.implicitHeight + 8
    radius: 8
    color: Commons.Color.menu.background
    border.width: 1
    border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.2)
    Text {
      id: label
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: cell.app.background ? cell.app.name + dock.tr(" — em segundo plano") : cell.app.name
      color: Commons.Color.menu.text
      font.pixelSize: 13
    }
  }

  // Right-click menu.
  AppMenu { dock: cell.dock; appCell: cell }

  // Window stack (WindowFan.qml): loaded while open and while it folds away.
  readonly property bool fanOn: dock.fanKey === cell.key
  property bool fanAlive: false
  onFanOnChanged: {
    if (fanOn) { fanAlive = true; if (fanLoader.item) fanLoader.item.open() }
    else if (fanLoader.item) fanLoader.item.close()
  }
  Loader {
    id: fanLoader
    active: cell.fanOn || cell.fanAlive
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.horizontalCenterOffset: -dock.spacing * cell.grow / 2
    anchors.bottom: parent.top
    width: 0
    height: 0
    sourceComponent: WindowFan { dock: cell.dock; appCell: cell; onClosed: cell.fanAlive = false }
  }

  MouseArea {
    id: tip
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    property bool hovered: containsMouse
    onContainsMouseChanged: dock.hoverApp(cell.key, containsMouse)
    preventStealing: true
    // Left button held and moved past a few pixels = drag, not click.
    property point pressAt
    property bool moved: false
    onPressed: function(m) {
      pressAt = Qt.point(m.x, m.y)
      moved = false
      if (m.button === Qt.LeftButton) cell.pressStart()
    }
    onPositionChanged: function(m) {
      if (!(pressedButtons & Qt.LeftButton)) return
      if (!moved) {
        if (Math.abs(m.x - pressAt.x) + Math.abs(m.y - pressAt.y) < 8) return
        moved = true
        pressDown.stop(); cell.press = 1
        dock.startDrag(cell.key)
      }
      var p = mapToItem(cell.parent, m.x, m.y)
      dock.dragTo(p.x, p.y)
    }
    onReleased: function(m) {
      if (moved) dock.endDrag()
      else if (m.button === Qt.LeftButton) cell.pressEnd()
    }
    onCanceled: { pressDown.stop(); cell.press = 1; if (moved) { moved = false; dock.endDrag() } }
    onClicked: function(m) {
      if (moved) return
      dock.fanKey = ""
      dock.fanOpen.stop()
      if (m.button === Qt.RightButton) dock.menuIndex = dock.menuIndex === cell.index ? -1 : cell.index
      else if (m.button === Qt.MiddleButton) dock.launch(cell.app)
      else { dock.menuIndex = -1; dock.activate(cell.app) }
    }
  }
}
