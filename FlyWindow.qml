import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import qs.Commons as Commons

// What a window does when it is picked from the stack above an icon:
//   start(): a minimized one flies from the stack into its place, growing,
//     drawn with a live copy of it on a full-screen, click-through overlay
//     that only exists for the flight (the dock's own surface is too short,
//     and resizing it makes the dock jump);
//   lightBorder(): one already in place gets its border lit in the accent
//     colour for a moment and faded back, drawn by Hyprland itself.
// Both can wait first (a workspace slide).
PanelWindow {
  id: fly
  required property var dock
  screen: dock.dockScreen
  visible: false
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  // Not "omarchy-dock…": the dock's Liquid Glass takes those namespaces and
  // would shade the whole screen.
  WlrLayershell.namespace: "hugorolimf-dock-fly"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  Component.onCompleted: dock.flyWindow = fly

  property var toplevel: null
  property rect from: Qt.rect(0, 0, 0, 0)
  property rect to: Qt.rect(0, 0, 0, 0)
  property real t: 0

  // toplevel: the Wayland toplevel; rects in this screen's coordinates;
  // wait: ms the thumbnail holds in the stack before it flies.
  function start(toplevel, from, to, wait) {
    flight.stop(); hold.stop()
    fly.toplevel = toplevel
    fly.from = from
    fly.to = to
    t = 0
    visible = true
    if (wait > 0) { hold.interval = wait; hold.restart() }
    else flight.restart()
  }
  Timer { id: hold; onTriggered: flight.restart() }
  NumberAnimation {
    id: flight
    target: fly; property: "t"; from: 0; to: 1
    duration: 300
    easing.type: Easing.InOutCubic
    onFinished: { fly.visible = false; fly.toplevel = null }
  }

  ClippingRectangle {
    x: fly.from.x + (fly.to.x - fly.from.x) * fly.t
    y: fly.from.y + (fly.to.y - fly.from.y) * fly.t
    width: fly.from.width + (fly.to.width - fly.from.width) * fly.t
    height: fly.from.height + (fly.to.height - fly.from.height) * fly.t
    radius: 12
    color: "transparent"
    ScreencopyView {
      anchors.fill: parent
      captureSource: fly.visible ? fly.toplevel : null
      live: true
      paintCursor: false
    }
  }

  // The lit border: the same width, only the colour turns to the accent
  // and, ~0.6 s later, fades back step by step to the border's own colour
  // (Hyprland jumps when a single colour goes back to a gradient), then the
  // override is dropped once it already looks the same.
  property string lit: ""
  property var home: ({ r: 1, g: 1, b: 1, a: 0.7 })
  function lightBorder(address, wait) {
    unlight(true)
    lit = "address:0x" + String(address).replace(/^0x/, "")
    borderQuery.running = false
    borderQuery.running = true
    lightOn.interval = Math.max(1, wait)
    lightOn.restart()
  }
  Process {
    id: borderQuery
    command: ["hyprctl", "getoption", "general:col.active_border"]
    stdout: StdioCollector { onStreamFinished: fly.readHome(text) }
  }
  // "gradient data: 98ffffff b8ffffff 80deg": the average of its colours (ARGB).
  function readHome(text) {
    var hexes = String(text).split("\n")[0].replace(/^[^:]*:\s*/, "").trim().split(/\s+/)
      .filter(function(p) { return /^[0-9a-fA-F]{8}$/.test(p) })
    if (hexes.length === 0) return
    var s = { r: 0, g: 0, b: 0, a: 0 }
    hexes.forEach(function(h) {
      s.a += parseInt(h.substr(0, 2), 16); s.r += parseInt(h.substr(2, 2), 16)
      s.g += parseInt(h.substr(4, 2), 16); s.b += parseInt(h.substr(6, 2), 16)
    })
    var n = hexes.length * 255
    home = { r: s.r / n, g: s.g / n, b: s.b / n, a: s.a / n }
  }
  Timer {
    id: lightOn
    onTriggered: { fly.setProps(fly.lit, [["active_border_color", fly.mix(0)]]); lightOff.restart() }
  }
  Timer { id: lightOff; interval: 600; onTriggered: fly.unlight(false) }
  // 0 = accent, 1 = the border's own colour.
  function mix(k) {
    var c = Commons.Color.accent
    function hex(v) { var h = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "rgba(" + hex(c.r + (home.r - c.r) * k) + hex(c.g + (home.g - c.g) * k)
      + hex(c.b + (home.b - c.b) * k) + hex(1 + (home.a - 1) * k) + ")"
  }
  Timer {
    id: fade
    interval: 45
    repeat: true
    property string sel: ""
    property int step: 0
    onTriggered: {
      step++
      if (step <= 10) fly.setProps(sel, [["active_border_color", fly.mix(step / 10)]])
      else { stop(); fly.setProps(sel, [["active_border_color", "unset"]]) }
    }
  }
  // now: put it back at once (another window is being lit).
  function unlight(now) {
    lightOn.stop(); lightOff.stop()
    if (fade.running) { fade.stop(); setProps(fade.sel, [["active_border_color", "unset"]]) }
    if (lit === "") return
    if (now) setProps(lit, [["active_border_color", "unset"]])
    else { fade.sel = lit; fade.step = 0; fade.restart() }
    lit = ""
  }
  function setProps(sel, pairs) {
    var cmds = pairs.map(function(p) {
      return 'hl.dsp.window.set_prop({ prop = "' + p[0] + '", value = "' + p[1] + '", window = "' + sel + '" })'
    })
    Quickshell.execDetached(["sh", "-c", 'for d in "$@"; do hyprctl dispatch "$d" >/dev/null; done', "sh"].concat(cmds))
  }
}
