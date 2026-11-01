import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Fourth layer of the dock (see DockCore): pins and drag to reorder, what
// the dock tells the windowing script (cover-<monitor>), and its IPC.
DockActions {
  id: root

  function savePins() {
    pinFile.setText(JSON.stringify(pinned, null, 2) + "\n")
  }

  // Pin/unpin animates in two steps: the icon shrinks away where it is, then
  // the change is applied and it grows back at its new spot (if it stays).
  function togglePin(item) {
    if (pinTimer.pending) return
    leavingKey = keyOf(item.id)
    pinTimer.pending = item
    pinTimer.restart()
  }

  function commitPin(item) {
    var next = pinned.filter(function(p) { return !matches(p, item.appId) })
    if (next.length === pinned.length) next.push(item.appId)
    pinned = next
    savePins()
    for (var i = 0; i < dockModel.count; i++)
      if (dockModel.get(i).key === leavingKey) { dockModel.remove(i); break }
    leavingKey = ""
    rebuild()
  }

  function modelIndex(key) {
    for (var i = 0; i < dockModel.count; i++) if (dockModel.get(i).key === key) return i
    return -1
  }

  function startDrag(key) {
    menuIndex = -1
    dragFrom = modelIndex(key)
    dragKey = key
  }

  // Neighbours make way as the icon passes their center.
  function dragTo(x, y) {
    dragX = x
    dragY = y
    var from = modelIndex(dragKey)
    if (from < 0 || dragRemoves) return
    var to = 0
    for (var i = 0; i < dockModel.count; i++) {
      var it = appRepeater ? appRepeater.itemAt(i) : null
      if (i !== from && it && it.x + it.width / 2 < x) to++
    }
    if (to !== from) dockModel.move(from, to, 1)
  }

  // The new order becomes the pinned order. Like macOS, an app that was
  // only running stays in the dock once it's been dragged to a new spot.
  function endDrag() {
    var key = dragKey
    var to = modelIndex(key)
    var removing = dragRemoves
    dragKey = ""
    if (removing) {
      poofKey = key
      poofTimer.restart()
      pinned = pinned.filter(function(p) { return keyOf(p) !== key })
      savePins()
    } else if (to >= 0 && to !== dragFrom) {
      var next = []
      for (var i = 0; i < dockModel.count; i++) {
        var k = dockModel.get(i).key
        var it = itemMap[k]
        if (!it || closing[k] !== undefined) continue
        if (it.pinned) next.push(it.id)
        else if (k === key) next.push(it.appId)
      }
      pinned = next
      savePins()
    }
    dragFrom = -1
    rebuild()
  }

  Timer {
    id: poofTimer
    interval: 260
    onTriggered: root.poofKey = ""
  }

  Timer {
    id: pinTimer
    property var pending: null
    interval: 190
    onTriggered: { var item = pending; pending = null; root.commitPin(item) }
  }


  function toggleAutoHide() { cfg.autoHide = !cfg.autoHide; return cfg.autoHide ? "autohide" : "fixed" }
  function open(payloadJson) {}
  function close() {}

  FileView {
    id: pinFile
    path: root.stateDir + "/pinned.json"
    watchChanges: true
    onLoaded: {
      try { root.pinned = JSON.parse(text()) } catch (e) {}
      root.rebuild()
      root.ready = true
    }
    onLoadFailed: { root.rebuild(); root.ready = true }
    onFileChanged: reload()
  }

  Connections {
    target: ToplevelManager.toplevels
    function onValuesChanged() { root.rebuild() }
  }
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.rebuild() }
  }
  Connections {
    target: root.cfg
    function onCurrentWorkspaceOnlyChanged() { root.rebuild() }
    function onMonitorAppsOnlyChanged() { root.rebuild() }
    function onShowMinimizedChanged() { root.rebuild() }
  }

  // Like macOS: while the dock stays on screen, windows snapped to an edge
  // (by a windowing script) stop above it. Each dock publishes two heights
  // on its monitor: what it covers right now (0 while it hides), then its
  // line, which ordinary windows never go past, even beside the dock and
  // while it steps aside for a maximized window (0 only with auto-hide on).
  readonly property string monitorName: monitor ? monitor.name : ""
  readonly property int dockHeight: Math.ceil(root.baseSize + root.pad * 2 + 2 + 6)
  readonly property int coverHeight: !autoHide && dockVisible ? dockHeight : 0
  readonly property int lineHeight: !cfg.autoHide && dockVisible ? dockHeight : 0
  function publishCover() {
    if (monitorName !== "") coverFile.setText(coverHeight + " " + lineHeight + "\n")
  }
  // A maximized window here grows into (or gives back) the dock's room; the
  // others keep above the line.
  onCoverHeightChanged: { publishCover(); refitSoon.restart() }
  onLineHeightChanged: { publishCover(); refitSoon.restart() }
  Timer {
    id: refitSoon
    interval: 60
    onTriggered: if (root.monitorName !== "")
      hyprEval("windowing_refit", root.monitorName, "")
  }
  onMonitorNameChanged: { Qt.callLater(publishCover); Qt.callLater(readMaximized) }
  FileView {
    id: coverFile
    path: root.monitorName !== "" ? root.stateDir + "/cover-" + root.monitorName : ""
  }

  IpcHandler {
    target: "dock"
    function toggleAutoHide(): string { return root.toggleAutoHide() }
    function state(): string { return root.autoHide ? "autohide" : "fixed" }
    function expose(app: string): void { root.expose(root.keyOf(app)) }
    function unexpose(): void { root.unexpose() }
    function fan(app: string): void { root.fanKey = root.keyOf(app) }
    function unfan(): void { root.fanKey = "" }
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    rebuild()
    publishCover()
  }
}
