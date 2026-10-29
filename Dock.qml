import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons

// macOS-style dock: pinned + running apps, hover magnification, auto-hide.
// Where macOS keeps Downloads/Trash, this dock shows the Hyprland workspaces
// of its monitor (mini icons of their windows; click/scroll to switch).
// Pinned apps live in ~/.local/state/omarchy/io.github.hugorolimf.dock/pinned.json (desktop-entry ids).
// Not in the plugin folder: the shell reloads every plugin when a file there changes.
// Look and behavior come from DockSettings (edited from the dock's bar panel).
// One instance per screen (see Main.qml), each with its monitor's workspaces.
// Toggle auto-hide: omarchy-shell shell call dock toggleAutoHide ""
Item {
  id: root

  // Portuguese is the source language; anything else gets English.
  readonly property bool portuguese: Qt.locale().name.indexOf("pt") === 0
  readonly property var english: ({" — minimizada": " — minimized", "Mostrar todas as janelas": "Show all windows", "Remover": "Remove", "Abrir nova janela": "New window", "Mover para a área ": "Move to workspace ", "Mover para uma área nova": "Move to a new workspace", "Minimizar": "Minimize", "Restaurar": "Restore", "Fechar janelas": "Close windows", "Encerrar app": "Quit app", "Fixar na dock": "Keep in Dock", "Desafixar da dock": "Remove from Dock", " — em segundo plano": " — running in the background"})
  function tr(text) { return portuguese ? text : (english[text] || text) }

  property var shell: null
  property var manifest: null
  // Screen this dock lives on; Main.qml makes one dock per screen.
  property var dockScreen: null

  DockSettings { id: settings }
  readonly property var cfg: settings.values

  // Like macOS with "automatically hide": besides the setting, the dock hides
  // while a maximized window fills this monitor's visible workspace (a
  // windowing script may list them in <stateDir>/maximized), and shows on hover.
  readonly property bool autoHide: cfg.autoHide || crowded
  property bool crowded: false
  function readMaximized() {
    var lines = String(maxFile.text() || "").split("\n"), busy = false
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split(" ")
      if (f.length >= 3 && Number(f[1]) === currentWs && f[2] === monitorName) busy = true
    }
    crowded = busy
  }
  FileView {
    id: maxFile
    path: root.stateDir + "/maximized"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readMaximized()
    onLoadFailed: root.crowded = false
  }
  property var pinned: []
  property var items: []
  property var itemMap: ({})
  // Apps still running with no window left (Super + W closes the window,
  // not the app): class key -> { id, pid }. Filled by bgPoll.
  property var bgApps: ({})
  // Icons added after the first load grow in; the initial set just appears.
  property bool ready: false
  property string leavingKey: ""
  // Rows on their way out (key -> time it started): kept in the model until
  // the shrink animation has played, then swept away.
  property var closing: ({})
  property var wsClosing: ({})
  // Apps launched from the dock (key -> { n: windows at launch, at }): their
  // icon bounces, like macOS, until a new window shows up.
  property var launching: ({})
  property int menuIndex: -1
  // App Exposé: the app whose windows are laid out (key), and whether it is
  // showing (it fades out before the key clears).
  property string exposeKey: ""
  // Hover fan: resting on an app with several windows fans them out above
  // its icon, like a macOS stack; click one to go to it. fanKey is the app
  // shown, fanWant the one under the pointer waiting for fanOpen.
  property string fanKey: ""
  property string fanWant: ""
  property bool exposeShown: false
  readonly property var exposeApp: exposeKey !== "" ? itemMap[exposeKey] || null : null
  onItemMapChanged: if (exposeShown && (!exposeApp || exposeApp.windows.length === 0)) unexpose()
  // Drag to reorder (like macOS): the key being dragged, the pointer x in
  // the icon strip and where the drag started.
  property string dragKey: ""
  property real dragX: 0
  property int dragFrom: -1
  property real dragY: 0
  // Like macOS: a pinned icon pulled well above the dock gets removed on drop.
  readonly property bool dragRemoves: dragKey !== "" && dragY < -baseSize * 0.9
    && !!itemMap[dragKey] && itemMap[dragKey].pinned
  // The icon just dropped off the dock: it vanishes where it was let go.
  property string poofKey: ""
  property real hoverX: -1000
  property bool hovering: false

  // Workspaces of the dock's monitor: [{ id, name, apps: [appId] }], special ones left out.
  property var workspaceList: []
  property var wsMap: ({})
  readonly property var monitor: win.screen ? Hyprland.monitorFor(win.screen) : null
  readonly property int currentWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id
    : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
  readonly property bool showWorkspaces: cfg.showWorkspaces && workspaceList.length > 0
  onCurrentWsChanged: { rebuild(); readMaximized() }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/io.github.hugorolimf.dock"
  // Like macOS, icons shrink when the dock would run past the screen width
  // (220 px covers the plate padding and the window's side room).
  readonly property real screenWidth: win.screen ? win.screen.width : 1920
  readonly property real fitUnits: items.length * 1.08 + (showWorkspaces ? workspaceList.length * 1.38 + 0.2 : 0)
  readonly property int fitSize: fitUnits > 0 ? Math.floor((screenWidth - 220) / fitUnits) : 96
  readonly property int baseSize: Math.max(24, Math.min(96, cfg.iconSize, fitSize))
  readonly property int tileWidth: Math.round(baseSize * 1.3)
  readonly property int miniSize: Math.max(8, Math.floor((baseSize - 14) / 2))
  // Tight like the macOS dock: small gaps and a thin plate around the icons.
  readonly property int spacing: Math.max(2, Math.round(baseSize * 0.08))
  readonly property int pad: Math.max(4, Math.round(baseSize * 0.12))
  readonly property real maxScale: cfg.magnify ? Math.max(1, cfg.maxScale) : 1
  // Where the icons sit with nothing magnified, in window coordinates; the
  // hover zoom is measured against this so it never feeds back into itself.
  readonly property real slot: baseSize + spacing
  readonly property real restWsWidth: showWorkspaces
    ? (spacing + 1) + spacing + workspaceList.length * tileWidth + Math.max(0, workspaceList.length - 1) * spacing : 0
  readonly property real restPlateWidth: dockModel.count * slot + restWsWidth + pad * 2 - (showWorkspaces ? 0 : spacing)
  readonly property real restStripLeft: (win.width - restPlateWidth) / 2 + pad
  // Room above the plate for magnified icons + name tooltip.
  readonly property int headroom: Math.ceil(baseSize * maxScale) + 50
  // Extra room for the right-click menu, which sits above the magnified icon.
  // Sized for up to 10 workspaces and never tied to the live count: a
  // surface that resizes when a workspace comes or goes makes the dock jump.
  readonly property int menuRoom: (6 + 10) * 30 + 24
  readonly property bool shown: !autoHide || hovering || menuIndex >= 0 || fanKey !== "" || dragKey !== "" || items.length === 0
  readonly property bool engaged: hovering || menuIndex >= 0 || fanKey !== "" || dragKey !== ""
  property real plateScale: cfg.compact && !autoHide && !engaged ? Math.max(0.3, Math.min(1, cfg.compactScale)) : 1
  Behavior on plateScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  function entryFor(appId) {
    if (!appId) return null
    return DesktopEntries.heuristicLookup(appId) || DesktopEntries.byId(appId) || null
  }

  // Qt caches icon theme lookups for the life of the process, so an app
  // installed after the shell started gets no themed icon until a restart.
  // When the theme misses, try the icon files on disk directly; the Image
  // steps through these candidates (iconTry) until one loads.
  readonly property var iconDirs: {
    var home = Quickshell.env("HOME")
    return [home + "/.local/share/icons/hicolor", "/usr/share/icons/hicolor",
            home + "/.local/share/flatpak/exports/share/icons/hicolor",
            "/var/lib/flatpak/exports/share/icons/hicolor"]
  }

  function iconCandidates(appId) {
    // Re-evaluate when apps are installed or removed.
    void DesktopEntries.applications.values
    var e = entryFor(appId)
    var tries = []
    if (e && e.icon) tries.push(e.icon)
    tries.push(appId, keyOf(appId), keyOf(appId) + "-browser")
    for (var i = 0; i < tries.length; i++) {
      var path = Quickshell.iconPath(tries[i], true)
      if (path) return [path]
    }
    var files = []
    var names = []
    for (var j = 0; j < 2 && j < tries.length; j++)
      if (tries[j] && names.indexOf(tries[j]) < 0) names.push(tries[j])
    names.forEach(function(name) {
      if (name.charAt(0) === "/") { files.push("file://" + name); return }
      iconDirs.forEach(function(dir) {
        files.push("file://" + dir + "/scalable/apps/" + name + ".svg")
        ;["256x256", "512x512", "128x128", "64x64", "48x48"].forEach(function(size) {
          files.push("file://" + dir + "/" + size + "/apps/" + name + ".png")
        })
      })
      files.push("file:///usr/share/pixmaps/" + name + ".svg", "file:///usr/share/pixmaps/" + name + ".png")
    })
    return files
  }

  function iconFor(list, attempt) {
    return list[attempt] || Quickshell.iconPath("application-x-executable", true)
  }

  function keyOf(appId) { return (appId || "").toLowerCase() }

  // Does a toplevel belong to a pinned id? Compare against the resolved
  // desktop entry id too, since appId and the .desktop name often differ.
  function matches(pin, appId) {
    var a = keyOf(appId), p = keyOf(pin)
    if (a === p) return true
    var e = entryFor(appId)
    return !!(e && keyOf(e.id) === p)
  }

  // Helper windows of other plugins (Liquid Glass test/tuner) aren't apps.
  function ignored(appId) {
    return appId.indexOf("org.omarchy.glass-test") === 0 || appId.indexOf("chrome-__run_user") === 0
  }

  function hyprAppId(tl) {
    if (tl.wayland && tl.wayland.appId) return tl.wayland.appId
    var ipc = tl.lastIpcObject
    return ipc && ipc["class"] ? ipc["class"] : ""
  }

  function rebuild() {
    // Mid-drag the model holds the order being dragged; endDrag rebuilds.
    if (dragKey !== "") return
    var tops = []
    try { tops = ToplevelManager.toplevels.values || [] } catch (e) {}
    var hypr = []
    try { hypr = Hyprland.toplevels.values || [] } catch (e) {}

    // Workspace + Hyprland address for each Wayland toplevel (same order as tops).
    var place = tops.map(function(t) {
      for (var h = 0; h < hypr.length; h++) {
        if (hypr[h].wayland !== t) continue
        var wsObj = hypr[h].workspace
        return { ws: wsObj ? wsObj.id : -1, address: String(hypr[h].address || ""),
                 mon: hypr[h].monitor || null,
                 minimized: !!(wsObj && String(wsObj.name) === "special:minimized") }
      }
      return { ws: -1, address: "", mon: null, minimized: false }
    })

    function addWindow(item, k) {
      item.windows.push(tops[k])
      item.places.push(place[k])
      if (place[k].minimized) item.minimized.push(place[k].address)
      else item.shown.push(tops[k])
      if (place[k].ws === currentWs) item.here.push(tops[k])
      if (!monitor || place[k].mon === monitor) item.onMonitor++
      if (place[k].ws > 0 && item.workspaces.indexOf(place[k].ws) < 0) item.workspaces.push(place[k].ws)
    }
    function newItem(id, isPinned) {
      var e = entryFor(id)
      return { id: id, appId: id, name: e ? e.name : id, pinned: isPinned, windows: [], places: [], here: [], workspaces: [], onMonitor: 0,
               shown: [], minimized: [] }
    }

    var used = ({})
    var out = []
    for (var i = 0; i < pinned.length; i++) {
      var pinItem = newItem(pinned[i], true)
      for (var j = 0; j < tops.length; j++) {
        if (matches(pinned[i], tops[j].appId)) { addWindow(pinItem, j); used[j] = true }
      }
      out.push(pinItem)
    }
    var extra = ({})
    for (var k = 0; k < tops.length; k++) {
      if (used[k] || !tops[k].appId || ignored(tops[k].appId)) continue
      var key = keyOf(tops[k].appId)
      if (extra[key] === undefined) {
        extra[key] = out.length
        out.push(newItem(tops[k].appId, false))
      }
      addWindow(out[extra[key]], k)
    }
    for (var w = 0; w < out.length; w++) out[w].workspaces.sort(function(a, b) { return a - b })
    // Running in the background: pinned ones get marked, others come back.
    for (var bk in bgApps) {
      var bg = bgApps[bk], found = false
      for (var b = 0; b < out.length; b++) {
        if (matches(out[b].id, bg.id) || keyOf(out[b].id) === bk) {
          found = true
          if (out[b].windows.length === 0) { out[b].background = true; out[b].bgPid = bg.pid }
        }
      }
      if (!found && !ignored(bg.id)) {
        var bgItem = newItem(bg.id, false)
        bgItem.background = true
        bgItem.bgPid = bg.pid
        out.push(bgItem)
      }
    }
    // "Only this workspace": pinned apps stay, running ones need a window here.
    if (cfg.currentWorkspaceOnly) out = out.filter(function(it) { return it.pinned || it.background || it.here.length > 0 || it.minimized.length > 0 })
    // "Only this monitor" (one dock per screen): running apps need a window on it.
    if (cfg.monitorAppsOnly) out = out.filter(function(it) { return it.pinned || it.background || it.onMonitor > 0 })

    var wsList = []
    var wsValues = []
    try { wsValues = Hyprland.workspaces.values || [] } catch (e) {}
    for (var s = 0; s < wsValues.length; s++) {
      var ws = wsValues[s]
      if (ws.id <= 0 || (monitor && ws.monitor && ws.monitor !== monitor)) continue
      var apps = []
      var wsTops = ws.toplevels ? ws.toplevels.values : []
      for (var t = 0; t < wsTops.length; t++) {
        var appId = hyprAppId(wsTops[t])
        if (appId && !ignored(appId)) apps.push(appId)
      }
      wsList.push({ id: ws.id, name: String(ws.name || ws.id), apps: apps })
    }
    wsList.sort(function(a, b) { return a.id - b.id })
    var wsm = ({})
    for (var q = 0; q < wsList.length; q++) wsm[String(wsList[q].id)] = wsList[q]
    // Closing tiles keep their last look while they shrink away.
    for (var c = 0; c < wsModel.count; c++) {
      var wk = wsModel.get(c).key
      if (!wsm[wk] && wsMap[wk]) wsm[wk] = wsMap[wk]
    }
    wsMap = wsm
    workspaceList = wsList
    wsClosing = syncList(wsModel, wsList.map(function(w) { return String(w.id) }), wsClosing)

    var map = ({})
    for (var m = 0; m < out.length; m++) map[keyOf(out[m].id)] = out[m]
    // Same for apps that just closed: last name/icon, no windows.
    for (var d = 0; d < dockModel.count; d++) {
      var dk = dockModel.get(d).key
      if (!map[dk] && itemMap[dk])
        map[dk] = Object.assign({}, itemMap[dk], { windows: [], places: [], here: [], workspaces: [] })
    }
    itemMap = map
    items = out
    closing = syncList(dockModel, out.map(function(it) { return keyOf(it.id) }), closing)

    // A launch is over once the app has a window more than when it started;
    // that new window comes to the front of everything.
    var still = ({}), changed = false
    for (var lk in launching) {
      if (map[lk] && map[lk].windows.length > launching[lk].n) {
        changed = true
        var known = launching[lk].addrs || []
        for (var p = 0; p < map[lk].places.length; p++) {
          var pa = map[lk].places[p] && map[lk].places[p].address
          if (pa && known.indexOf(pa) < 0) { raise(pa); break }
        }
      } else still[lk] = launching[lk]
    }
    if (changed) launching = still

    // Background apps: an app seen with a window that just lost its last one
    // stays in the dock right away (bgPoll confirms the process is alive);
    // a window coming or going makes bgPoll look again soon, so even a window
    // open for a moment gets its app remembered.
    var nowWin = ({}), winChanged = false, bgNext = null
    for (var t = 0; t < tops.length; t++) if (tops[t].appId) nowWin[keyOf(tops[t].appId)] = true
    for (var pk in prevWin) {
      if (nowWin[pk]) continue
      winChanged = true
      if (bgSeen[pk] && !bgApps[pk]) { bgNext = bgNext || Object.assign({}, bgApps); bgNext[pk] = bgSeen[pk] }
    }
    for (var nk in nowWin) if (!prevWin[nk]) winChanged = true
    prevWin = nowWin
    if (winChanged) bgSoon.restart()
    if (bgNext) { bgApps = bgNext; Qt.callLater(rebuild) }
  }
  property var prevWin: ({})
  Timer { id: bgSoon; interval: 400; onTriggered: bgTick() }

  // Update a { key } ListModel in place so only rows that really appear or
  // disappear get (re)created; a fresh array would re-animate every delegate.
  // Rows that are gone stay (marked in the returned closing map) until
  // closeSweep removes them, so their delegates can shrink away first.
  function syncList(model, want, wasClosing) {
    var now = Date.now()
    var gone = ({})
    for (var r = 0; r < model.count; r++) {
      var k = model.get(r).key
      if (want.indexOf(k) < 0) gone[k] = wasClosing[k] || now
    }
    var pos = 0
    for (var i = 0; i < want.length; i++) {
      while (pos < model.count && gone[model.get(pos).key]) pos++
      if (pos < model.count && model.get(pos).key === want[i]) { pos++; continue }
      var from = -1
      for (var j = pos + 1; j < model.count; j++) if (model.get(j).key === want[i]) { from = j; break }
      if (from >= 0) model.move(from, pos, 1)
      else model.insert(pos, { key: want[i] })
      pos++
    }
    if (Object.keys(gone).length > 0 && !closeSweep.running) closeSweep.start()
    return gone
  }

  function sweep(model, gone) {
    var now = Date.now(), left = ({}), any = false
    for (var r = model.count - 1; r >= 0; r--) {
      var k = model.get(r).key
      if (!gone[k]) continue
      if (now - gone[k] >= 220) model.remove(r)
      else { left[k] = gone[k]; any = true }
    }
    return { left: left, any: any }
  }

  Timer {
    id: closeSweep
    interval: 240
    onTriggered: {
      var a = root.sweep(dockModel, root.closing)
      var w = root.sweep(wsModel, root.wsClosing)
      root.closing = a.left
      root.wsClosing = w.left
      if (a.any || w.any) restart()
    }
  }

  Timer {
    id: launchTimeout
    interval: 1000
    repeat: true
    running: Object.keys(root.launching).length > 0
    onTriggered: {
      var now = Date.now(), still = ({})
      for (var k in root.launching) if (now - root.launching[k].at < 10000) still[k] = root.launching[k]
      root.launching = still
    }
  }

  // Every few seconds: which apps have windows (class + pid), and which of
  // the apps that had them are still alive without any. Cheap: one hyprctl
  // call and a /proc check per remembered pid.
  property var bgSeen: ({})   // class key -> { id, pid } of apps seen with a window
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
    Qt.callLater(function() { exposeRoot.forceActiveFocus() })
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
    Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "$1" >/dev/null && hyprctl eval "$2"', "sh",
      'hl.dsp.window.move({ workspace = "' + currentWs + '", window = "address:' + a + '", follow = false })',
      'if windowing_raise then windowing_raise("' + a + '") else hl.dispatch(hl.dsp.focus({ window = "address:' + a + '" })) end'])
  }

  function dispatch(lua) { Quickshell.execDetached(["hyprctl", "dispatch", lua]) }

  function focusWorkspace(id) { dispatch('hl.dsp.focus({ workspace = "' + id + '" })') }

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
      var it = appRepeater.itemAt(i)
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

  ListModel { id: dockModel }
  ListModel { id: wsModel }

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
  }

  // Like macOS: while the dock stays on screen, windows snapped to an edge
  // (by a windowing script) stop above it. Each dock publishes the height it
  // covers on its monitor; 0 while it auto-hides.
  readonly property string monitorName: monitor ? monitor.name : ""
  readonly property int coverHeight: !autoHide && win.visible ? Math.ceil(root.baseSize + root.pad * 2 + 2 + 6) : 0
  function publishCover() {
    if (monitorName !== "") coverFile.setText(String(coverHeight) + "\n")
  }
  // A maximized window here grows into (or gives back) the dock's room.
  onCoverHeightChanged: { publishCover(); refitSoon.restart() }
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

  Timer {
    id: fanOpen
    interval: 250
    onTriggered: if (root.fanWant !== "") root.fanKey = root.fanWant
  }
  Timer {
    id: fanClose
    interval: 300
    onTriggered: root.fanKey = ""
  }

  Timer {
    id: exposeEnd
    interval: 200
    onTriggered: root.exposeKey = ""
  }

  // App Exposé (macOS "Show All Windows"): the screen dims and the app's
  // windows sit side by side, live; click one to go to it, anywhere else
  // (or Esc) to leave. Opens on this dock's monitor.
  PanelWindow {
    id: exposeWin
    screen: root.dockScreen
    visible: root.exposeKey !== ""
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock-expose"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Item {
      id: exposeRoot
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.unexpose()
      opacity: root.exposeShown ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      readonly property var app: root.exposeApp
      readonly property int n: app ? app.windows.length : 0
      readonly property int cols: n <= 3 ? Math.max(1, n) : Math.ceil(Math.sqrt(n))
      readonly property int rows: Math.max(1, Math.ceil(n / cols))
      readonly property real gap: 32
      readonly property real label: 36
      readonly property real tileW: Math.min(560, (width * 0.86 - gap * (cols - 1)) / cols,
                                             ((height * 0.72 - gap * (rows - 1)) / rows - label) * 1.6)

      Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
      MouseArea { anchors.fill: parent; onClicked: root.unexpose() }

      Grid {
        anchors.centerIn: parent
        columns: exposeRoot.cols
        spacing: exposeRoot.gap
        scale: root.exposeShown ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Repeater {
          model: exposeRoot.n
          Item {
            id: etile
            required property int index
            readonly property var toplevel: exposeRoot.app ? exposeRoot.app.windows[index] : null
            readonly property var place: (exposeRoot.app && exposeRoot.app.places || [])[index] || ({})
            width: exposeRoot.tileW
            height: exposeRoot.tileW / 1.6 + exposeRoot.label

            Rectangle {
              anchors.fill: eshot
              anchors.margins: -6
              radius: 12
              color: "transparent"
              border.width: 3
              border.color: Commons.Color.accent
              opacity: tileMouse.containsMouse ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 120 } }
            }

            // The live window, or the app's icon until a frame arrives.
            Item {
              id: eshot
              anchors { top: parent.top; left: parent.left; right: parent.right }
              height: parent.height - exposeRoot.label
              opacity: etile.place.minimized ? 0.55 : 1

              // Solid backing: translucent windows (the terminal) would
              // otherwise show the screen behind through the thumbnail.
              Rectangle {
                anchors.fill: eview
                visible: eview.hasContent
                radius: 8
                color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, 1)
              }

              ScreencopyView {
                id: eview
                readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height * aspect)
                height: Math.min(parent.height, parent.width / aspect)
                captureSource: root.exposeShown && etile.toplevel ? etile.toplevel : null
                live: true
                paintCursor: false
                constraintSize: Qt.size(width * 2, height * 2)
                visible: hasContent
                layer.enabled: true
                layer.smooth: true
              }

              Image {
                anchors.centerIn: parent
                visible: !eview.hasContent
                width: Math.min(parent.width, parent.height) * 0.45
                height: width
                sourceSize: Qt.size(256, 256)
                source: exposeRoot.app ? root.iconFor(root.iconCandidates(exposeRoot.app.appId), 0) : ""
                smooth: true
                mipmap: true
              }
            }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              width: Math.min(parent.width, etitle.implicitWidth + 20)
              height: 26
              radius: 13
              color: Commons.Color.menu.background
              Text {
                id: etitle
                textFormat: Text.PlainText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.parent.width - 20)
                elide: Text.ElideRight
                text: (etile.toplevel && etile.toplevel.title || (exposeRoot.app ? exposeRoot.app.name : ""))
                      + (etile.place.minimized ? root.tr(" — minimizada") : "")
                color: Commons.Color.menu.text
                font.pixelSize: 13
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                var app = exposeRoot.app, i = etile.index
                root.unexpose()
                if (app) root.goToWindow(app, i)
              }
            }
          }
        }
      }
    }
  }

  PanelWindow {
    id: win
    screen: root.dockScreen
    visible: root.items.length > 0 || root.pinned.length > 0
    anchors { bottom: true; left: true; right: true }
    // Fixed size (full width, fixed height): resizing the surface while
    // magnifying makes the pointer leave/enter it, and resizing it when a
    // workspace comes or goes makes the whole dock jump for a few frames.
    implicitHeight: root.headroom + root.menuRoom
    color: "transparent"
    WlrLayershell.namespace: "omarchy-dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // With a windowing script the dock floats over the windows and the script
    // keeps them clear of it (cover-<monitor> files); without one it reserves
    // its height like a bar, so tiled windows stop above it.
    exclusionMode: root.hasWindowing ? ExclusionMode.Ignore : ExclusionMode.Normal
    exclusiveZone: root.hasWindowing ? 0 : root.coverHeight
    // Only the visible dock (or a thin strip on the screen edge while hidden) takes input.
    mask: Region { item: hit }

    Item {
      id: hit
      readonly property bool resting: root.plateScale < 1 && !root.hovering
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      width: root.fanKey !== "" ? parent.width
        : root.menuIndex >= 0 ? Math.min(parent.width, plate.width + 260)
        : resting ? plate.width * root.plateScale + 8 : plate.width + 20
      height: !root.shown ? 4
        : root.menuIndex >= 0 || root.fanKey !== "" ? parent.height
        : resting ? plate.height * root.plateScale + 6 : root.headroom
    }

    Timer {
      id: hideDelay
      interval: 400
      onTriggered: { root.hovering = false; root.menuIndex = -1; root.fanKey = "" }
    }

    // Like macOS: while hidden, the pointer has to rest on the screen edge
    // for a moment before the dock slides in, so passing by doesn't summon it.
    Timer {
      id: revealDelay
      interval: Math.round(Math.max(0, root.cfg.revealDelay) * 1000)
      onTriggered: root.hovering = true
    }

    // Everything lives inside this item so hovering an icon or the menu
    // still counts as hovering the dock (a sibling MouseArea got "exited").
    Item {
      anchors.fill: parent

      HoverHandler {
        onHoveredChanged: {
          if (hovered) {
            hideDelay.stop()
            if (root.shown) root.hovering = true
            else revealDelay.restart()
          } else {
            revealDelay.stop()
            root.hoverX = -1000
            hideDelay.restart()
          }
        }
        // Up in an open fan the icons hold still (the fan hangs off one).
        onPointChanged: if (hovered && !(root.fanKey !== "" && point.position.y < plate.y)) root.hoverX = point.position.x
      }

    Rectangle {
      id: plate
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.shown ? 6 : -(height + 12)
      // Compact while the mouse is away; full size as soon as it arrives.
      scale: root.plateScale
      transformOrigin: Item.Bottom
      // App cells carry the spacing themselves (so it animates away with
      // them); the last one's trailing gap is dropped unless workspaces follow.
      // Workspace tiles carry their trailing gap too.
      width: content.implicitWidth + root.pad * 2 - root.spacing
      height: root.baseSize + root.pad * 2 + 2
      radius: Math.round(root.baseSize * 0.3)
      color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, root.cfg.opacity)
      border.width: 1
      border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.18)
      Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

      Row {
        id: content
        x: root.pad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad + 2
        spacing: 0

      Row {
        id: strip
        anchors.bottom: parent.bottom
        spacing: 0
        // Only while dragging: neighbours slide aside. Otherwise it would
        // also lag the magnification, which moves icons constantly.
        move: root.dragKey !== "" ? slideAside : null
        Transition {
          id: slideAside
          NumberAnimation { properties: "x"; duration: 160; easing.type: Easing.OutCubic }
        }

        Repeater {
          id: appRepeater
          model: dockModel
          delegate: Item {
            id: cell
            required property string key
            required property int index
            readonly property bool dragging: root.dragKey === key
            z: dragging || root.fanKey === key ? 5 : 0
            readonly property var app: root.itemMap[key] || ({ id: key, appId: key, name: key, pinned: false, windows: [] })
            // From the resting layout, like macOS: using the live x/width
            // made zoom depend on itself (binding loop, wasted CPU).
            readonly property real centerX: root.restStripLeft + index * root.slot + root.slot / 2
            readonly property real dist: Math.abs(root.hoverX - centerX)
            readonly property real zoom: root.hovering && root.hoverX > -500
              ? 1 + (root.maxScale - 1) * Math.exp(-(dist * dist) / (2 * Math.pow(root.baseSize * 1.15, 2))) : 1
            // 0..1: grows in when added (app opened), shrinks away when
            // (un)pinned or when its last window closes.
            property real grow: root.ready ? 0 : 1
            readonly property bool going: root.leavingKey === key || root.closing[key] !== undefined
            Component.onCompleted: grow = going ? 0 : 1
            onGoingChanged: grow = going ? 0 : 1
            // Grows in unhurried; shrinking stays quick (pinTimer and closeSweep wait on it).
            Behavior on grow { NumberAnimation { duration: cell.going ? 180 : 360; easing.type: cell.going ? Easing.OutCubic : Easing.OutBack } }

            // Launch bounce: a smooth, continuous up-and-down (no rest between
            // hops) until the new window appears. Then it stops right where it
            // is and the icon glides down from that height (no extra hop).
            readonly property bool bouncing: root.launching[key] !== undefined
            readonly property real bounceHeight: root.baseSize * 0.4
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
            readonly property bool poofing: root.poofKey === key
            readonly property bool lifted: (dragging && root.dragRemoves) || poofing
            property real poof: poofing ? 0 : 1
            Behavior on poof { NumberAnimation { duration: 180; easing.type: Easing.InCubic } }

            width: (root.baseSize * zoom + root.spacing) * grow * (lifted ? 0 : 1)
            height: root.baseSize * zoom
            anchors.bottom: parent.bottom
            Behavior on width { enabled: cell.grow === 1; NumberAnimation { duration: 70 } }
            Behavior on height { NumberAnimation { duration: 70 } }

            // The icon is drawn a bit smaller than its slot and raised, so the
            // running dot sits inside the slot under it (the plate keeps its size).
            Image {
              // Centred on the icon's own room: the slot also carries the gap
              // to the next icon on its right.
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: -root.spacing * cell.grow / 2
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Math.round(root.baseSize * cell.zoom * 0.17)
              width: root.baseSize * cell.zoom * 0.80
              height: width
              scale: cell.grow * cell.poof
              opacity: cell.grow * (cell.lifted ? 0.6 : 1)
              transformOrigin: cell.poofing ? Item.Center : Item.Bottom
              // Follows the pointer while dragged (upwards too, to pull it
              // off), then glides into its slot. After a removal it jumps
              // home unseen instead (poof is still 0 at that moment).
              transform: Translate {
                id: shift
                readonly property bool held: cell.dragging || cell.poofing
                readonly property bool glide: !held && cell.poof === 1
                x: held ? root.dragX - (cell.x + cell.width / 2) : 0
                y: held ? Math.min(0, root.dragY - (cell.y + cell.height / 2)) : -cell.lift
                Behavior on x { enabled: shift.glide; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on y { enabled: shift.glide && !cell.bouncing && !settle.running; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
              }

              // root.tr("Remover") above the icon while dropping it would unpin it.
              Rectangle {
                visible: cell.dragging && root.dragRemoves
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
                  text: root.tr("Remover")
                  color: Commons.Color.menu.text
                  font.pixelSize: 13
                }
              }
              property var iconList: root.iconCandidates(cell.app.appId)
              property int iconTry: 0
              onIconListChanged: iconTry = 0
              source: root.iconFor(iconList, iconTry)
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
              readonly property int active: on && !background ? root.activeWindow(cell.app) : -1
              spacing: 3
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: -root.spacing * cell.grow / 2
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
              readonly property var others: (cell.app.workspaces || []).filter(function(w) { return w !== root.currentWs })
              readonly property string label: others.length <= 2 ? others.join("·")
                : others.slice(0, 2).join("·") + "+" + (others.length - 2)
              visible: root.cfg.workspaceBadges && cell.grow === 1 && others.length > 0
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.rightMargin: root.spacing / 2 - 3
              anchors.topMargin: -3
              width: Math.max(height, badgeText.implicitWidth + 8)
              height: Math.max(14, Math.round(root.baseSize * 0.32))
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
              visible: tip.hovered && root.menuIndex < 0 && root.fanKey !== cell.key && root.dragKey === ""
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
                text: cell.app.background ? cell.app.name + root.tr(" — em segundo plano") : cell.app.name
                color: Commons.Color.menu.text
                font.pixelSize: 13
              }
            }

            // Right-click menu.
            Rectangle {
              visible: root.menuIndex === cell.index
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.top
              anchors.bottomMargin: 8
              width: 210
              height: menuCol.implicitHeight + 12
              radius: 10
              color: Commons.Color.menu.background
              border.width: 1
              border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
              z: 10
              Column {
                id: menuCol
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2
                Repeater {
                  model: {
                    var app = cell.app
                    var m = []
                    // The app's windows by title, like macOS: ✓ the one in
                    // focus, ◆ minimized ones.
                    var act = root.activeWindow(app)
                    for (var wi = 0; wi < Math.min(app.windows.length, 6); wi++) {
                      var pl = (app.places || [])[wi] || {}
                      m.push({ t: app.windows[wi].title || app.name, a: "win", i: wi,
                               mark: wi === act ? "✓" : pl.minimized ? "◆" : "" })
                    }
                    if (app.windows.length > 1) m.push({ t: root.tr("Mostrar todas as janelas"), a: "expose" })
                    m = m.concat([
                      { t: root.tr("Abrir nova janela"), a: "new" },
                      { t: app.pinned ? root.tr("Desafixar da dock") : root.tr("Fixar na dock"), a: "pin" }
                    ])
                    if (root.cfg.moveMenu && app.windows.length > 0) {
                      var only = app.workspaces.length === 1 ? app.workspaces[0] : -1
                      for (var i = 0; i < root.workspaceList.length; i++) {
                        var w = root.workspaceList[i]
                        if (w.id !== only) m.push({ t: root.tr("Mover para a área ") + w.name, a: "move", ws: String(w.id) })
                      }
                      m.push({ t: root.tr("Mover para uma área nova"), a: "move", ws: "emptynm" })
                    }
                    if ((app.shown || []).length > 0) m.push({ t: root.tr("Minimizar"), a: "min" })
                    if ((app.minimized || []).length > 0) m.push({ t: root.tr("Restaurar"), a: "restore" })
                    m.push({ t: root.tr("Fechar janelas"), a: "close", off: app.windows.length === 0 })
                    m.push({ t: root.tr("Encerrar app"), a: "quit", off: app.windows.length === 0 && !app.background })
                    return m
                  }
                  delegate: Rectangle {
                    required property var modelData
                    visible: !modelData.off
                    width: menuCol.width
                    height: modelData.off ? 0 : 28
                    radius: 6
                    color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                    Text {
                      textFormat: Text.PlainText
                      visible: !!modelData.mark
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: 8
                      text: modelData.mark || ""
                      color: Commons.Color.menu.text
                      font.pixelSize: 11
                    }
                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.left: parent.left
                      anchors.leftMargin: modelData.a === "win" ? 24 : 8
                      width: parent.width - anchors.leftMargin - 8
                      elide: Text.ElideRight
                      text: modelData.t
                      color: Commons.Color.menu.text
                      font.pixelSize: 13
                      font.weight: modelData.a === "win" ? Font.Medium : Font.Normal
                    }
                    MouseArea {
                      id: ma
                      anchors.fill: parent
                      hoverEnabled: true
                      onClicked: {
                        var item = cell.app
                        root.menuIndex = -1
                        if (modelData.a === "win") root.goToWindow(item, modelData.i)
                        else if (modelData.a === "expose") root.expose(cell.key)
                        else if (modelData.a === "new") root.launch(item)
                        else if (modelData.a === "pin") root.togglePin(item)
                        else if (modelData.a === "move") root.moveToWorkspace(item, modelData.ws)
                        else if (modelData.a === "min") root.minimize(item)
                        else if (modelData.a === "restore") root.restore(item)
                        else if (modelData.a === "quit") root.quitApp(item)
                        else for (var i = 0; i < item.windows.length; i++) item.windows[i].close()
                      }
                    }
                  }
                }
              }
            }

            // Window fan: the app's windows open side by side above the
            // icon, spread like a hand of cards (middle ones highest, the
            // outer ones tilted out), each titled underneath.
            Loader {
              active: root.fanKey === cell.key
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.horizontalCenterOffset: -root.spacing * cell.grow / 2
              anchors.bottom: parent.top
              width: 0
              height: 0
              sourceComponent: Item {
                id: fan
                readonly property var app: cell.app
                readonly property int n: app.windows.length
                readonly property real label: 28
                readonly property real cardW: Math.min(170, win.width * 0.9 / Math.max(1, n))
                // Negative: neighbours overlap a little, like cards held in a hand.
                readonly property real gap: -cardW * 0.1
                readonly property real cardH: cardW / 1.6
                readonly property real rowW: n * cardW + (n - 1) * gap
                // Kept on screen: slides sideways when the icon is near an edge.
                readonly property real iconX: cell.centerX - root.spacing / 2
                readonly property real shift: Math.max(16 + rowW / 2 - iconX, Math.min(0, win.width - 16 - rowW / 2 - iconX))
                readonly property real mid: (n - 1) / 2
                Repeater {
                  model: fan.n
                  Item {
                    id: card
                    required property int index
                    readonly property var toplevel: fan.app.windows[index]
                    readonly property var place: (fan.app.places || [])[index] || ({})
                    readonly property bool active: toplevel === ToplevelManager.activeToplevel
                    readonly property real c: index - fan.mid
                    property real open: 0
                    width: fan.cardW
                    height: fan.cardH
                    // Opens out of the icon into its spot on the arc.
                    x: -width / 2 + open * (c * (fan.cardW + fan.gap) + fan.shift)
                    y: -height - fan.label - 10 - open * (6 + (fan.mid * fan.mid - c * c) * 4)
                    rotation: open * c * 4
                    // The card under the pointer comes on top of its neighbours.
                    z: cardMouse.containsMouse ? 1 : 0
                    transformOrigin: Item.Bottom
                    // Scale only, no fade: the dock's Liquid Glass is cut by alpha.
                    scale: 0.35 + 0.65 * open
                    NumberAnimation on open {
                      from: 0; to: 1
                      duration: 280
                      easing.type: Easing.OutCubic
                    }

                    // Same glass as the plate (the fan lives on the dock's layer),
                    // so translucent windows like the terminal look as they do.
                    Rectangle {
                      anchors.fill: parent
                      radius: 12
                      antialiasing: true
                      color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, root.cfg.opacity)
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
                        source: root.iconFor(root.iconCandidates(fan.app.appId), 0)
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
                        : Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, Math.max(0.36, root.cfg.opacity))
                      border.width: 1
                      border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.16)
                      Text {
                        id: ctitle
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, card.width * 0.85 - 16)
                        elide: Text.ElideRight
                        text: (card.toplevel && card.toplevel.title || fan.app.name) + (card.place.minimized ? root.tr(" — minimizada") : "")
                        color: Commons.Color.menu.text
                        font.pixelSize: 12
                      }
                    }
                    MouseArea {
                      id: cardMouse
                      anchors.fill: parent
                      anchors.bottomMargin: -fan.label
                      hoverEnabled: true
                      onContainsMouseChanged: root.fanHover(containsMouse)
                      onClicked: {
                        var app = fan.app, i = card.index
                        root.fanKey = ""
                        root.goToWindow(app, i)
                      }
                    }
                  }
                }
              }
            }

            MouseArea {
              id: tip
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
              property bool hovered: containsMouse
              onContainsMouseChanged: root.hoverApp(cell.key, containsMouse)
              preventStealing: true
              // Left button held and moved past a few pixels = drag, not click.
              property point pressAt
              property bool moved: false
              onPressed: function(m) { pressAt = Qt.point(m.x, m.y); moved = false }
              onPositionChanged: function(m) {
                if (!(pressedButtons & Qt.LeftButton)) return
                if (!moved) {
                  if (Math.abs(m.x - pressAt.x) + Math.abs(m.y - pressAt.y) < 8) return
                  moved = true
                  root.startDrag(cell.key)
                }
                var p = mapToItem(strip, m.x, m.y)
                root.dragTo(p.x, p.y)
              }
              onReleased: if (moved) root.endDrag()
              onCanceled: if (moved) { moved = false; root.endDrag() }
              onClicked: function(m) {
                if (moved) return
                root.fanKey = ""
                fanOpen.stop()
                if (m.button === Qt.RightButton) root.menuIndex = root.menuIndex === cell.index ? -1 : cell.index
                else if (m.button === Qt.MiddleButton) root.launch(cell.app)
                else { root.menuIndex = -1; root.activate(cell.app) }
              }
            }
          }
        }
      }

      // Separator between apps and workspaces, like the one before macOS's stacks.
      Item {
        visible: root.showWorkspaces
        width: visible ? root.spacing + 1 : 0
        height: root.baseSize
        anchors.bottom: parent.bottom
        Rectangle {
          anchors.centerIn: parent
          width: 1
          height: parent.height * 0.75
          color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
        }
      }

      // Workspaces of this monitor: number + mini icons of their windows.
      // Click to switch; scroll to step through them. Tiles grow in/shrink
      // away as workspaces come and go, and the highlight slides to the
      // active one.
      Item {
        id: wsBox
        visible: root.showWorkspaces
        anchors.bottom: parent.bottom
        implicitWidth: wsRow.implicitWidth
        implicitHeight: root.baseSize

        property bool wheelReady: true
        Timer { id: wheelGate; interval: 180; onTriggered: wsBox.wheelReady = true }
        WheelHandler {
          onWheel: function(event) {
            if (!wsBox.wheelReady || event.angleDelta.y === 0) return
            wsBox.wheelReady = false
            wheelGate.restart()
            root.stepWorkspace(event.angleDelta.y < 0 ? 1 : -1)
          }
        }

        // The tile cell of the active workspace; cells set it themselves. A
        // stale one is kept (just hidden) so the highlight slides from there.
        property Item activeCell: null

        Rectangle {
          id: wsHighlight
          visible: wsBox.activeCell !== null && wsBox.activeCell.active
          // Slides toward the active tile, centred on it while it pops in.
          // When workspaces come and go at once (a new one created from a
          // brand new, now empty one) the target moves under the slide and
          // it could overshoot past the dock's edge: the slide is clamped to
          // the tiles' own room.
          property real slideX: wsBox.activeCell ? wsBox.activeCell.x + (root.tileWidth - width) / 2 : 0
          Behavior on slideX { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          x: Math.max(0, Math.min(slideX, wsBox.width - width))
          width: root.tileWidth * (wsBox.activeCell ? wsBox.activeCell.pop : 1)
          height: root.baseSize
          scale: width > 0 ? 1 : 0
          radius: Math.round(root.baseSize * 0.2)
          color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.28)
          border.width: 1
          border.color: Commons.Color.accent
        }

      Row {
        id: wsRow
        anchors.bottom: parent.bottom
        leftPadding: root.spacing
        spacing: 0

        Repeater {
          model: wsModel
          // Each cell carries its trailing gap, so it animates away with the tile.
          delegate: Item {
            id: wsCell
            required property string key
            readonly property var ws: root.wsMap[key] || ({ id: Number(key), name: key, apps: [] })
            readonly property bool active: Number(key) === root.currentWs
            // Two steps, so a tile never spills past the plate: the dock
            // first opens room for it (open), then the tile pops in inside
            // that room (pop). Closing runs the other way round, within the
            // ~220 ms the close sweep waits before removing the row.
            // Set once at creation (a binding to root.ready would zero them
            // again when the dock finishes loading): tiles there from the
            // start just appear, later ones animate in.
            property real open: 0
            property real pop: 0
            readonly property bool going: root.wsClosing[key] !== undefined
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
              if (!root.ready && !going) { open = 1; pop = 1 }
              settle()
              if (active) wsBox.activeCell = wsCell
            }
            Component.onDestruction: if (wsBox.activeCell === wsCell) wsBox.activeCell = null
            onGoingChanged: settle()
            onActiveChanged: if (active) wsBox.activeCell = wsCell
            width: (root.tileWidth + root.spacing) * open
            height: root.baseSize

          Rectangle {
            id: tile
            readonly property bool active: wsCell.active
            // Joined, so the mini icons are only recreated when the list really changes.
            readonly property string appsKey: wsCell.ws.apps.join("\n")
            readonly property var apps: appsKey ? appsKey.split("\n") : []
            readonly property int shownApps: apps.length > 4 ? 3 : apps.length
            width: root.tileWidth
            height: root.baseSize
            scale: wsCell.pop
            opacity: wsCell.pop
            transformOrigin: Item.Bottom
            radius: Math.round(root.baseSize * 0.2)
            // The active fill comes from the sliding highlight underneath.
            color: active
              ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, tileMouse.containsMouse ? 0.12 : 0)
              : Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, tileMouse.containsMouse ? 0.16 : 0.07)
            border.width: active ? 0 : 1
            border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.12)
            Behavior on color { ColorAnimation { duration: 160 } }

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: 5
              anchors.verticalCenter: parent.verticalCenter
              text: wsCell.ws.name
              color: Commons.Color.menu.text
              opacity: tile.active ? 1 : 0.7
              Behavior on opacity { NumberAnimation { duration: 160 } }
              font.pixelSize: Math.max(9, Math.round(root.baseSize * 0.24))
              font.bold: tile.active
            }

            Grid {
              anchors.right: parent.right
              anchors.rightMargin: 5
              anchors.verticalCenter: parent.verticalCenter
              columns: 2
              spacing: 2
              Repeater {
                model: tile.apps.slice(0, tile.shownApps)
                Image {
                  id: mini
                  required property var modelData
                  width: root.miniSize
                  height: width
                  property var iconList: root.iconCandidates(modelData)
                  property int iconTry: 0
                  onIconListChanged: iconTry = 0
                  source: root.iconFor(iconList, iconTry)
                  onStatusChanged: if (status === Image.Error) Qt.callLater(() => iconTry++)
                  sourceSize: Qt.size(128, 128)
                  smooth: true
                  mipmap: true
                  fillMode: Image.PreserveAspectFit
                  // Pops in when a window lands on this workspace.
                  scale: root.ready ? 0.4 : 1
                  Component.onCompleted: scale = 1
                  Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: tile.apps.length > 4
                width: root.miniSize
                height: width
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "+" + (tile.apps.length - 3)
                color: Commons.Color.menu.text
                font.pixelSize: Math.max(8, Math.round(root.miniSize * 0.5))
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              onClicked: { root.menuIndex = -1; root.focusWorkspace(wsCell.ws.id) }
            }
          }
          }
        }
      }
      }
      }
    }
    }
  }

  Component.onCompleted: {
    windowingProbe.running = true
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    rebuild()
    publishCover()
  }
}
