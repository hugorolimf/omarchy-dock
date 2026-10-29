import QtQuick
import Quickshell
import Quickshell.Io

// Dock settings shared by the dock and its bar panel. They live in
// ~/.local/state/omarchy/io.github.hugorolimf.dock/settings.json, outside the plugin folder:
// the shell reloads every plugin whenever a file in that folder is written.
FileView {
  id: file

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/io.github.hugorolimf.dock"
  property alias values: values

  path: stateDir + "/settings.json"
  watchChanges: true
  onFileChanged: reload()
  onAdapterUpdated: writeAdapter()
  onLoadFailed: function(error) {
    if (error !== FileViewError.FileNotFound) return
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    writeAdapter()
  }

  JsonAdapter {
    id: values
    property bool autoHide: true
    property real revealDelay: 0.4
    property bool compact: false
    property real compactScale: 0.6
    property int iconSize: 48
    property bool magnify: true
    property real maxScale: 1.7
    property real opacity: 0.72
    property bool liquidGlass: false
    property bool showWorkspaces: true
    property bool workspaceBadges: true
    property bool moveMenu: true
    property bool currentWorkspaceOnly: false
    property bool monitorAppsOnly: false
  }
}
