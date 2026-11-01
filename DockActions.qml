import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Third layer of the dock (see DockCore): what clicking, the menu and the
// fan do to apps and windows, and the Hyprland events that refresh it.
DockModel {
  id: root

  // Every few seconds: which apps have windows (class + pid), and which of
  // the apps that had them are still alive without any. Cheap: one hyprctl
  // call and a /proc check per remembered pid.
  Process {
    id: bgProc
    stdout: StdioCollector {
      onStreamFinished: {
        var seen = Object.assign({}, root.bgSeen), withWin = ({}), alive = ({})
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].split("\t")
          if (f[0] === "W" && f[1] && Number(f[2]) > 0) {
            var k = root.keyOf(f[1])
            withWin[k] = true
            seen[k] = { id: f[1], pid: Number(f[2]) }
          } else if (f[0] === "A") alive[f[1]] = true
        }
        var bg = ({}), changed = false
        for (var key in seen) {
          if (withWin[key]) continue
          if (alive[String(seen[key].pid)] && !root.ignored(seen[key].id)) bg[key] = seen[key]
          else delete seen[key]
        }
        root.bgSeen = seen
        if (JSON.stringify(bg) !== JSON.stringify(root.bgApps)) { root.bgApps = bg; root.rebuild() }
      }
    }
  }
  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.bgTick()
  }
  function bgTick() {
    if (bgProc.running) { bgSoon.restart(); return }
    var pids = []
    for (var k in root.bgSeen) pids.push(String(root.bgSeen[k].pid))
    bgProc.command = ["sh", "-c",
      'hyprctl clients | awk \'/^\tclass: /{c=$2} /^\tpid: /{printf "W\\t%s\\t%s\\n", c, $2}\'; ' +
      'for p in "$@"; do [ -d /proc/$p ] && printf "A\\t%s\\n" "$p"; done', "sh"].concat(pids)
    bgProc.running = true
  }
  // Window actions go through a windowing script when the user has one
  // (it defines windowing_raise, windowing_minimize, ... in the Hyprland Lua
  // config, adding animations and z-order care); otherwise the dock falls
  // back to plain Hyprland dispatchers, so it works on a stock Omarchy.
  function hyprEval(fn, arg, fallback) {
    Quickshell.execDetached(["hyprctl", "eval",
      "if " + fn + " then " + fn + '("' + arg + '") else ' + (fallback || "") + " end"])
  }
  // Whether the Hyprland config defines the windowing_* functions; checked at
  // start and after every config reload.
  property bool hasWindowing: false
  Process {
    id: windowingProbe
    command: ["hyprctl", "eval", 'if not windowing_raise then error("none") end']
    onExited: function(code) { root.hasWindowing = code === 0 }
  }
  function addr(address) { return "0x" + String(address).replace(/^0x/, "").replace(/[^0-9a-fA-F]/g, "") }

  // Quit the whole app (not just its windows): every window of its class
  // closes (a windowing script may instead end the process, keeping web apps
  // apart), or a plain TERM for one left running in the background.
  function quitApp(item) {
    if (item.windows.length > 0) {
      var cls = String(item.windows[0].appId || item.id).replace(/["\\]/g, "")
      hyprEval("windowing_quit", cls,
        'for _, w in ipairs(hl.get_windows() or {}) do if w.class == "' + cls + '" then ' +
        'hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address })) end end')
    } else if (item.bgPid > 0) {
      Quickshell.execDetached(["kill", "-TERM", String(item.bgPid)])
    }
  }

  function activeWindow(item) {
    var act = ToplevelManager.activeToplevel
    for (var i = 0; i < item.windows.length; i++) if (item.windows[i] === act) return i
    return -1
  }

  function launch(item) {
    var l = Object.assign({}, launching)
    l[keyOf(item.id)] = { n: item.windows.length, at: Date.now(),
                          addrs: item.places.map(function(p) { return p && p.address }) }
    launching = l
    var e = entryFor(item.id)
    if (e) e.execute()
    else Quickshell.execDetached([item.id])
  }

  // Click: launch if closed, otherwise focus (cycling through windows). With
  // "only this workspace", windows here come first; Hyprland follows the focus.
  //   all windows minimized      -> bring the last one back
  //   its only window is focused -> minimize it (like the Windows taskbar)
  function activate(item) {
    if (item.windows.length === 0) { launch(item); return }
    if (item.shown.length === 0) { restore(item); return }
    var active = ToplevelManager.activeToplevel
    if (item.shown.length === 1 && item.shown[0] === active) { minimize(item); return }
    var pool = cfg.currentWorkspaceOnly && item.here.length > 0 ? item.here : item.shown
    var cur = pool.indexOf(active)
    var next = pool[(cur + 1) % pool.length]
    var idx = item.windows.indexOf(next)
    var addr = idx >= 0 && item.places[idx] ? item.places[idx].address : ""
    if (addr) raise(addr)
    else next.activate()
  }

  // Focus a window and put it above every other one (all windows float, so
  // focusing alone can leave it behind others).
  function raise(address) {
    var a = addr(address)
    hyprEval("windowing_raise", a,
      'hl.dispatch(hl.dsp.focus({ window = "address:' + a + '" })) ' +
      'hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = "address:' + a + '" }))')
  }

  // Minimized windows sit on the hidden special:minimized workspace; they
  // come back to the workspace shown on this dock's monitor.
  function minimize(item) {
    var i = activeWindow(item)
    var place = item.places[i < 0 ? 0 : i]
    for (var k = 0; k < item.places.length && (!place || place.minimized); k++) place = item.places[k]
    if (place && place.address && !place.minimized)
      hyprEval("windowing_minimize", addr(place.address),
        'hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", window = "address:' + addr(place.address) + '", follow = false }))')
  }

  // The pointer entered/left an app's icon. Several windows: open its fan
  // after a short rest (at once if another fan is already open).
  function hoverApp(key, inside) {
    if (inside) {
      var it = itemMap[key]
      fanWant = it && it.windows.length > 1 && menuIndex < 0 && dragKey === "" ? key : ""
      if (fanWant === "") { fanOpen.stop(); if (fanKey !== "") fanClose.restart() }
      else if (fanKey !== "") { fanClose.stop(); fanKey = fanWant }
      else fanOpen.restart()
    } else if (fanWant === key) {
      fanWant = ""
      fanOpen.stop()
      if (fanKey === key) fanClose.restart()
    }
  }
  // The pointer is on (or left) a card of the open fan.
  function fanHover(inside) { if (inside) fanClose.stop(); else fanClose.restart() }

  // App Exposé (macOS "Show All Windows").
  function expose(key) {
    menuIndex = -1
    exposeEnd.stop()
    exposeKey = key
    exposeShown = true
  }
  function unexpose() {
    exposeShown = false
    exposeEnd.restart()
  }

  // Go to one of the app's windows: back from minimized, or raised.
  function goToWindow(item, i) {
    var place = item.places[i]
    if (place && place.minimized) restoreAddress(place.address)
    else if (place && place.address) raise(place.address)
    else if (item.windows[i]) item.windows[i].activate()
  }

  function restore(item) { restoreAddress(item.minimized[item.minimized.length - 1]) }
  function restoreAddress(address) {
    if (!address || currentWs <= 0) return
    var a = addr(address)
    // The windowing script puts it back on the workspace it was minimized from.
    if (hasWindowing) { hyprEval("windowing_restore", a, ""); return }
    Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "$1" >/dev/null && hyprctl eval "$2"', "sh",
      'hl.dsp.window.move({ workspace = "' + currentWs + '", window = "address:' + a + '", follow = false })',
      'if windowing_raise then windowing_raise("' + a + '") else hl.dispatch(hl.dsp.focus({ window = "address:' + a + '" })) end'])
  }

  function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }

  function focusWorkspace(id) { dispatch('hl.dsp.focus({ workspace = "' + id + '" })') }

  // Two workspaces swap their windows (one dragged onto the other). With the
  // Omarchy windowing script, windows keep their place and the screen keeps
  // showing the same windows; without it, every window just changes number.
  function swapWorkspaces(a, b) {
    a = Number(a); b = Number(b)
    if (!(a > 0) || !(b > 0) || a === b) return
    Quickshell.execDetached(["hyprctl", "eval",
      'if windowing_swap_workspaces then windowing_swap_workspaces(' + a + ', ' + b + ') else ' +
      'local all, moves = hl.get_windows() or {}, {} ' +
      'for i = 1, #all do local w = all[i]; local id = w.workspace and w.workspace.id; ' +
      'if (id == ' + a + ' or id == ' + b + ') and not w.pinned then moves[#moves + 1] = { w.address, id == ' + a + ' and ' + b + ' or ' + a + ' } end end ' +
      'for i = 1, #moves do hl.dispatch(hl.dsp.window.move({ workspace = tostring(moves[i][2]), window = "address:" .. moves[i][1], follow = false })) end end'])
  }

  // Scroll over the workspaces: step to the previous/next one in the list.
  function stepWorkspace(delta) {
    var ids = workspaceList.map(function(w) { return w.id })
    var i = ids.indexOf(currentWs)
    var next = ids[Math.max(0, Math.min(ids.length - 1, (i < 0 ? 0 : i) + delta))]
    if (next !== undefined && next !== currentWs) focusWorkspace(next)
  }

  // Moves the app's active window (or its first one) like Super+Shift+N does:
  // focus that window, then move the focused window, so the view follows it.
  function moveToWorkspace(item, ws) {
    var i = activeWindow(item)
    var place = item.places[i < 0 ? 0 : i]
    if (!place || !place.address) return
    var target = "address:0x" + place.address.replace(/^0x/, "")
    Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "$1" >/dev/null && hyprctl dispatch "$2"', "sh",
      'hl.dsp.focus({ window = "' + target + '" })',
      'hl.dsp.window.move({ workspace = "' + ws + '" })'])
  }

  // Hyprland events that change which windows sit on which workspace.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") windowingProbe.running = true
      switch (event.name) {
      case "openwindow": case "closewindow": case "movewindow": case "movewindowv2":
      case "createworkspace": case "createworkspacev2": case "destroyworkspace": case "destroyworkspacev2":
      case "moveworkspace": case "moveworkspacev2": case "renameworkspace": case "workspace": case "workspacev2":
        hyprRefresh.restart()
      }
    }
  }
  Timer {
    id: hyprRefresh
    interval: 80
    onTriggered: { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); root.rebuild(); hyprSettle.restart() }
  }
  // The refreshes above answer asynchronously; read them once they've landed.
  Timer {
    id: hyprSettle
    interval: 200
    onTriggered: root.rebuild()
  }

  // Hover fan and Exposé timing; pieces of the dock window use them too.
  property Timer fanOpen: Timer {
    interval: 250
    onTriggered: if (root.fanWant !== "") root.fanKey = root.fanWant
  }
  property Timer fanClose: Timer {
    interval: 300
    onTriggered: root.fanKey = ""
  }
  property Timer exposeEnd: Timer {
    interval: 200
    onTriggered: root.exposeKey = ""
  }

  Component.onCompleted: windowingProbe.running = true
}
