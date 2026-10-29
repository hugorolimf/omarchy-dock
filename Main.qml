import Quickshell
import QtQuick

// Panel entry point: one dock per screen, like the Windows taskbar. Docks
// follow screens being plugged in and out. Settings and pins are shared
// files, so every dock stays in step.
Item {
  id: root

  property var shell: null
  property var manifest: null

  Variants {
    model: Quickshell.screens
    delegate: Dock {
      required property var modelData
      shell: root.shell
      manifest: root.manifest
      dockScreen: modelData
    }
  }

  function open(payloadJson) {}
  function close() {}
}
