import Quickshell.Io
import QtQuick

// Recording mode: while <stateDir>/vitrine exists, listing workspace ids
// (space or newline separated; "21=1" also shows 21 as "1"), the dock only sees the windows and the
// workspaces on those (background apps only if pinned), so a demo can be recorded
// beside a working desktop. Delete the file and it is all back at once.
Item {
  id: v
  required property var dock
  property var ids: []
  property var names: ({})
  readonly property bool on: ids.length > 0
  function has(ws) { return ids.indexOf(Number(ws)) >= 0 }
  function label(ws) { return names[Number(ws)] || String(ws) }

  FileView {
    path: v.dock.stateDir + "/vitrine"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: v.read(text())
    onLoadFailed: v.read("")
  }
  function read(t) {
    var parts = String(t || "").split(/\s+/).filter(function(s) { return s !== "" })
    var next = [], nm = {}
    parts.forEach(function(s) {
      var kv = s.split("="), n = Number(kv[0])
      if (n > 0) { next.push(n); if (kv[1]) nm[n] = kv[1] }
    })
    if (JSON.stringify([next, nm]) === JSON.stringify([ids, names])) return
    ids = next
    names = nm
    Qt.callLater(dock.rebuild)
  }
}
