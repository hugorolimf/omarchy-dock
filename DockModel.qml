import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Second layer of the dock (see DockCore): which apps, workspaces and
// minimized windows it shows, kept in its models, and apps left running
// in the background.
DockCore {
  id: root

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
    // Recording mode (DockVitrine): only windows on its workspaces.
    if (vitrine.on) {
      var leftWs = minimizedFrom()
      var keep = place.map(function(pl) { return vitrine.has(pl.minimized ? leftWs[root.addr(pl.address)] : pl.ws) })
      tops = tops.filter(function(t, i) { return keep[i] })
      place = place.filter(function(pl, i) { return keep[i] })
    }

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
      if (!found && !ignored(bg.id) && !vitrine.on) {
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
      if (ws.id <= 0 || (monitor && ws.monitor && ws.monitor !== monitor) || (vitrine.on && !vitrine.has(ws.id))) continue
      var apps = []
      var wsTops = ws.toplevels ? ws.toplevels.values : []
      for (var t = 0; t < wsTops.length; t++) {
        var appId = hyprAppId(wsTops[t])
        if (appId && !ignored(appId)) apps.push(appId)
      }
      wsList.push({ id: ws.id, name: vitrine.on ? vitrine.label(ws.id) : String(ws.name || ws.id), apps: apps, minApps: [] })
    }
    // Minimized windows still belong to the workspace they left (the
    // windowing script keeps it in windowing-minimized): its tile shows them.
    var from = minimizedFrom()
    for (var mt = 0; mt < tops.length; mt++) {
      if (!place[mt].minimized || !tops[mt].appId || ignored(tops[mt].appId)) continue
      for (var wl = 0; wl < wsList.length; wl++)
        if (wsList[wl].id === from[root.addr(place[mt].address)]) wsList[wl].minApps.push(tops[mt].appId)
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

    // Minimized windows: ones already down keep their spot, new ones go last.
    var minNow = ({})
    for (var mk = 0; mk < tops.length; mk++) {
      if (place[mk].minimized && place[mk].address && tops[mk].appId && !ignored(tops[mk].appId))
        minNow[root.addr(place[mk].address)] = { toplevel: tops[mk], appId: tops[mk].appId }
    }
    var order = minOrder.filter(function(a) { return minNow[a] !== undefined })
    for (var na in minNow) if (order.indexOf(na) < 0) order.push(na)
    var mm = ({}), wentDown = false
    for (var mo = 0; mo < order.length; mo++) {
      mm[order[mo]] = minNow[order[mo]]
      if (ready && !minMap[order[mo]]) wentDown = true
    }
    for (var mr = 0; mr < minModel.count; mr++) {
      var mrk = minModel.get(mr).key
      if (!mm[mrk] && minMap[mrk]) mm[mrk] = minMap[mrk]
    }
    minMap = mm
    minOrder = order
    minClosing = syncList(minModel, cfg.showMinimized ? order : [], minClosing)
    if (wentDown && cfg.showMinimized) peek()

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
          // Recording mode: a window born on another workspace stays there.
          var away = vitrine.on && map[lk].places[p].ws !== root.currentWs
          if (pa && known.indexOf(pa) < 0) { if (!away) root.raise(pa); break }
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
  DockVitrine { id: vitrine; dock: root }
  function wsLabel(id) { return vitrine.on ? vitrine.label(id) : String(id) }

  // address -> workspace a minimized window left (windowing-minimized lines:
  // address x y w h tiled workspace).
  FileView {
    id: minFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/windowing-minimized"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.rebuild()
  }
  // Where a minimized window comes back (x y w h of its line, from the
  // monitor's work area), or null.
  function minimizedRect(address) {
    var text = ""
    try { text = String(minFile.text() || "") } catch (e) {}
    var lines = text.split("\n"), a = addr(address)
    for (var i = 0; i < lines.length; i++) {
      var f = lines[i].split(" ")
      if (f.length >= 5 && addr(f[0]) === a) return { x: Number(f[1]), y: Number(f[2]), w: Number(f[3]), h: Number(f[4]) }
    }
    return null
  }
  function minimizedFrom() {
    var out = ({}), text = ""
    try { text = String(minFile.text() || "") } catch (e) {}
    text.split("\n").forEach(function(l) {
      var f = l.split(" ")
      if (f.length >= 7 && Number(f[6]) > 0) out[f[0]] = Number(f[6])
    })
    return out
  }
  property Timer bgSoon: Timer { interval: 400; onTriggered: root.bgTick() }

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
      var n = root.sweep(minModel, root.minClosing)
      root.closing = a.left
      root.wsClosing = w.left
      root.minClosing = n.left
      if (a.any || w.any || n.any) restart()
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


}
