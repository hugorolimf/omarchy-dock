import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Base of the dock (Dock.qml builds on it in layers: DockModel, DockActions,
// DockPins): settings, sizes and the state every layer and piece shares,
// plus app icons. Functions of later layers are called as root.<name>().
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
  property var bgSeen: ({})   // class key -> { id, pid } of apps seen with a window
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
  // Stacks still folding into their icon: the dock keeps their room
  // (and stays up) until they are gone.
  property int fanClosing: 0
  readonly property bool fanUp: fanKey !== "" || fanClosing > 0
  property bool exposeShown: false
  readonly property var exposeApp: exposeKey !== "" ? itemMap[exposeKey] || null : null
  onItemMapChanged: if (exposeShown && (!exposeApp || exposeApp.windows.length === 0)) root.unexpose()
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
  readonly property var monitor: dockScreen ? Hyprland.monitorFor(dockScreen) : null
  readonly property int currentWs: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id
    : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1)
  readonly property bool showWorkspaces: cfg.showWorkspaces && workspaceList.length > 0
  onCurrentWsChanged: { root.rebuild(); readMaximized() }

  // Minimized windows, like macOS: each gets a thumbnail of its own at the
  // right end of the dock, in the order they went down. minOrder holds their
  // addresses, minMap address -> { toplevel, appId } (closing tiles keep
  // their last look while they shrink away).
  property var minOrder: []
  property var minMap: ({})
  property var minClosing: ({})
  readonly property bool minShown: cfg.showMinimized && minOrder.length > 0
  // A window just went down: an auto-hidden dock slides up for a moment, so
  // you see where it went (only on the monitor in focus).
  property bool peeking: false
  Timer { id: peekEnd; interval: 1400; onTriggered: root.peeking = false }
  function peek() {
    if (!autoHide || (Hyprland.focusedMonitor && monitor && Hyprland.focusedMonitor !== monitor)) return
    peeking = true
    peekEnd.restart()
  }

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/io.github.hugorolimf.dock"
  // Like macOS, icons shrink when the dock would run past the screen width
  // (220 px covers the plate padding and the window's side room).
  readonly property real screenWidth: dockScreen ? dockScreen.width : 1920
  readonly property real fitUnits: items.length * 1.08 + (showWorkspaces ? workspaceList.length * 1.38 + 0.2 : 0)
    + (minShown ? minOrder.length * 1.08 + 0.2 : 0)
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
  // Each section: its separator, the row's leading gap, then cells that carry
  // their trailing gap (the plate drops the very last one).
  readonly property real restWsWidth: showWorkspaces ? (spacing + 1) + spacing + workspaceList.length * (tileWidth + spacing) : 0
  readonly property real restMinWidth: minShown ? (spacing + 1) + spacing + minOrder.length * slot : 0
  readonly property real restPlateWidth: dockModel.count * slot + restWsWidth + restMinWidth + pad * 2 - spacing
  readonly property real restStripLeft: (screenWidth - restPlateWidth) / 2 + pad
  // Room above the plate for magnified icons + name tooltip.
  readonly property int headroom: Math.ceil(baseSize * maxScale) + 50
  // Extra room for the right-click menu, which sits above the magnified icon.
  // Sized for up to 10 workspaces and never tied to the live count: a
  // surface that resizes when a workspace comes or goes makes the dock jump.
  readonly property int menuRoom: (6 + 10) * 30 + 24
  // A window being dragged (WindowDrop.qml): the dock shows up to take it,
  // dropWs is the workspace tile under the pointer, landedWs the one that
  // just took a window (its tile bounces).
  property bool windowDragging: false
  property int dropWs: -1
  property int landedWs: -1
  // The workspace strip and the dock window (the drop needs tile places).
  property Item wsStrip: null
  property var dockWindow: null
  // FlyWindow: a picked window's thumbnail flies from the stack into it.
  property var flyWindow: null
  readonly property bool shown: !autoHide || hovering || peeking || windowDragging || menuIndex >= 0 || fanUp || dragKey !== "" || items.length === 0
  readonly property bool engaged: hovering || menuIndex >= 0 || fanUp || dragKey !== ""
  property real plateScale: cfg.compact && !autoHide && !engaged ? Math.max(0.3, Math.min(1, cfg.compactScale)) : 1
  Behavior on plateScale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

  // Rows of the app strip, the workspace tiles and the minimized windows.
  readonly property ListModel dockModel: ListModel {}
  readonly property ListModel wsModel: ListModel {}
  readonly property ListModel minModel: ListModel {}
  // The app strip's Repeater (DockWindow sets it), for drag to reorder.
  property Item appRepeater: null
  readonly property bool dockVisible: items.length > 0 || pinned.length > 0

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
    var plain = []
    if (cfg.plainIcons) {
      askPlain(tries[0])
      if (plainIcons[tries[0]]) plain.push("file://" + plainIcons[tries[0]])
    }
    return plain.concat(themedIcons(tries))
  }

  function themedIcons(tries) {
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

  // Some apps paint a dark plate behind their logo (Obsidian, Zen). The script
  // keeps a copy without it in the cache; icons without a plate stay as they are.
  property var plainIcons: ({})   // icon name -> clean file
  property var plainAsked: ({})
  property var plainQueue: []

  function askPlain(name) {
    if (plainAsked[name]) return
    plainAsked[name] = true
    plainQueue.push(name)
    Qt.callLater(nextPlain)
  }

  function nextPlain() {
    if (plainProc.running || plainQueue.length === 0) return
    plainProc.command = ["bash", String(Qt.resolvedUrl("strip-plate.sh")).replace("file://", ""),
      (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/glass-dock/plain-icons"].concat(plainQueue)
    plainQueue = []
    plainProc.running = true
  }

  Process {
    id: plainProc
    stdout: StdioCollector {
      onStreamFinished: {
        var found = Object.assign({}, root.plainIcons), changed = false
        text.split("\n").forEach(function(line) {
          var f = line.split("\t")
          if (f.length === 2) { found[f[0]] = f[1]; changed = true }
        })
        if (changed) root.plainIcons = found
      }
    }
    onExited: root.nextPlain()
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
}
