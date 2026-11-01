import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// The dock itself (one per screen): the plate with the app strip, the
// workspace tiles and the minimized windows, hover and auto-hide.
PanelWindow {
  id: win
  required property var dock
  screen: dock.dockScreen
  visible: dock.items.length > 0 || dock.pinned.length > 0
  anchors { bottom: true; left: true; right: true }
  // Fixed size (full width, fixed height): resizing the surface while
  // magnifying makes the pointer leave/enter it, and resizing it when a
  // workspace comes or goes makes the whole dock jump for a few frames.
  implicitHeight: dock.headroom + dock.menuRoom
  color: "transparent"
  WlrLayershell.namespace: "omarchy-dock"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // With a windowing script the dock floats over the windows and the script
  // keeps them clear of it (cover-<monitor> files); without one it reserves
  // its height like a bar, so tiled windows stop above it.
  exclusionMode: dock.hasWindowing ? ExclusionMode.Ignore : ExclusionMode.Normal
  exclusiveZone: dock.hasWindowing ? 0 : dock.coverHeight
  // Only the visible dock (or a thin strip on the screen edge while hidden) takes input.
  mask: Region { item: hit }
  // Liquid Glass (mask_mode "alpha_region") only works inside this box: the
  // input area while the dock is up, the plate while it slides away. Once the
  // plate is off the surface the box is empty and the glass skips the layer,
  // instead of shading the whole full-width surface every frame. 2 px of slack
  // keep the plate's antialiased edge (often on a half pixel) inside it.
  BackgroundEffect.blurRegion: Region { item: glassArea }
  Item {
    id: glassArea
    x: (dock.shown ? hit.x : plate.x) - 2
    y: (dock.shown ? hit.y : plate.y) - 2
    width: (dock.shown ? hit.width : plate.width) + 4
    height: dock.shown ? hit.height + 4 : Math.max(0, Math.min(plate.height + 4, win.height - plate.y + 2))
  }

  Item {
    id: hit
    readonly property bool resting: dock.plateScale < 1 && !dock.hovering
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    width: dock.fanUp ? parent.width
      : dock.menuIndex >= 0 ? Math.min(parent.width, plate.width + 260)
      : resting ? plate.width * dock.plateScale + 8 : plate.width + 20
    height: !dock.shown ? 4
      : dock.menuIndex >= 0 || dock.fanUp ? parent.height
      : resting ? plate.height * dock.plateScale + 6 : dock.headroom
  }

  Timer {
    id: hideDelay
    interval: 400
    onTriggered: { dock.hovering = false; dock.menuIndex = -1; dock.fanKey = "" }
  }

  // Like macOS: while hidden, the pointer has to rest on the screen edge
  // for a moment before the dock slides in, so passing by doesn't summon it.
  Timer {
    id: revealDelay
    interval: Math.round(Math.max(0, dock.cfg.revealDelay) * 1000)
    onTriggered: dock.hovering = true
  }

  // Everything lives inside this item so hovering an icon or the menu
  // still counts as hovering the dock (a sibling MouseArea got "exited").
  Item {
    anchors.fill: parent

    HoverHandler {
      onHoveredChanged: {
        if (hovered) {
          hideDelay.stop()
          if (dock.shown) dock.hovering = true
          else revealDelay.restart()
        } else {
          revealDelay.stop()
          dock.hoverX = -1000
          hideDelay.restart()
        }
      }
      // Up in an open fan the icons hold still (the fan hangs off one).
      onPointChanged: if (hovered && !(dock.fanKey !== "" && point.position.y < plate.y)) dock.hoverX = point.position.x
    }

  Rectangle {
    id: plate
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: dock.shown ? 6 : -(height + 12)
    // Compact while the mouse is away; full size as soon as it arrives.
    scale: dock.plateScale
    transformOrigin: Item.Bottom
    // App cells carry the spacing themselves (so it animates away with
    // them); the last one's trailing gap is dropped unless workspaces follow.
    // Workspace tiles carry their trailing gap too.
    width: content.implicitWidth + dock.pad * 2 - dock.spacing
    height: dock.baseSize + dock.pad * 2 + 2
    radius: Math.round(dock.baseSize * 0.3)
    color: Qt.rgba(Commons.Color.menu.background.r, Commons.Color.menu.background.g, Commons.Color.menu.background.b, dock.cfg.opacity)
    border.width: 1
    border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.18)
    Behavior on anchors.bottomMargin { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    Row {
      id: content
      x: dock.pad
      anchors.bottom: parent.bottom
      anchors.bottomMargin: dock.pad + 2
      spacing: 0

    Row {
      id: strip
      anchors.bottom: parent.bottom
      spacing: 0
      // Only while dragging: neighbours slide aside. Otherwise it would
      // also lag the magnification, which moves icons constantly.
      move: dock.dragKey !== "" ? slideAside : null
      Transition {
        id: slideAside
        NumberAnimation { properties: "x"; duration: 160; easing.type: Easing.OutCubic }
      }

      Repeater {
        id: appRepeater
        model: win.dock.dockModel
          delegate: AppCell { dock: win.dock }
        }
      }

    // Separator between apps and workspaces, like the one before macOS's stacks.
    Item {
      visible: dock.showWorkspaces
      width: visible ? dock.spacing + 1 : 0
      height: dock.baseSize
      anchors.bottom: parent.bottom
      Rectangle {
        anchors.centerIn: parent
        width: 1
        height: parent.height * 0.75
        color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
      }
    }

      WorkspaceStrip { dock: win.dock }

    // Minimized windows, like macOS: a thumbnail of each at the right end,
    // its app's icon in the corner. Click one to bring it back.
    Item {
      visible: dock.cfg.showMinimized && dock.minModel.count > 0
      width: visible ? dock.spacing + 1 : 0
      height: dock.baseSize
      anchors.bottom: parent.bottom
      Rectangle {
        anchors.centerIn: parent
        width: 1
        height: parent.height * 0.75
        color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
      }
    }

      MinimizedStrip { dock: win.dock }
      }
    }
    }

  Component.onCompleted: { dock.appRepeater = appRepeater; dock.dockWindow = win }
}
