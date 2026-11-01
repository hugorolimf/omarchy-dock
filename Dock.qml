import QtQuick

// macOS-style dock: pinned + running apps, hover magnification, auto-hide.
// Where macOS keeps Downloads/Trash, this dock shows the Hyprland workspaces
// of its monitor (mini icons of their windows; click/scroll to switch, drag
// one onto another to swap them, drag a window onto one with Super to send
// it there).
// Pinned apps live in ~/.local/state/omarchy/io.github.hugorolimf.dock/pinned.json (desktop-entry ids).
// Not in the plugin folder: the shell reloads every plugin when a file there changes.
// Look and behavior come from DockSettings (edited from the dock's bar panel).
// One instance per screen (see Main.qml), each with its monitor's workspaces.
// Toggle auto-hide: omarchy-shell shell call dock toggleAutoHide ""
//
// The logic is built in layers, each extending the one before: DockCore
// (settings, sizes, shared state, icons) -> DockModel (what it shows) ->
// DockActions (what clicks do) -> DockPins (pins, cover, IPC). The pieces on
// screen get the dock as `dock`: DockWindow (with AppCell, AppMenu,
// WindowFan, WorkspaceStrip, MinimizedStrip), ExposeWindow, FlyWindow and
// WindowDrop.
DockPins {
  id: root

  ExposeWindow { dock: root }
  FlyWindow { dock: root }
  DockWindow { dock: root }
  WindowDrop { dock: root }
}
