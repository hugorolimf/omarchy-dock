import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// App Exposé (macOS "Show All Windows"): the screen dims and the app's
// windows sit side by side, live; click one to go to it, anywhere else
// (or Esc) to leave. Opens on this dock's monitor.
PanelWindow {
  id: exposeWin
  required property var dock
  screen: dock.dockScreen
  visible: dock.exposeKey !== ""
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "hugorolimf-dock-expose"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Item {
    id: exposeRoot
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: dock.unexpose()
    Connections {
      target: exposeWin.dock
      function onExposeShownChanged() { if (exposeWin.dock.exposeShown) exposeRoot.forceActiveFocus() }
    }
    opacity: dock.exposeShown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    readonly property var app: dock.exposeApp
    readonly property int n: app ? app.windows.length : 0
    readonly property int cols: n <= 3 ? Math.max(1, n) : Math.ceil(Math.sqrt(n))
    readonly property int rows: Math.max(1, Math.ceil(n / cols))
    readonly property real gap: 32
    readonly property real label: 36
    readonly property real tileW: Math.min(560, (width * 0.86 - gap * (cols - 1)) / cols,
                                           ((height * 0.72 - gap * (rows - 1)) / rows - label) * 1.6)

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    MouseArea { anchors.fill: parent; onClicked: dock.unexpose() }

    Grid {
      anchors.centerIn: parent
      columns: exposeRoot.cols
      spacing: exposeRoot.gap
      scale: dock.exposeShown ? 1 : 0.94
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
              captureSource: dock.exposeShown && etile.toplevel ? etile.toplevel : null
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
              source: exposeRoot.app ? dock.iconFor(dock.iconCandidates(exposeRoot.app.appId), 0) : ""
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
                    + (etile.place.minimized ? dock.tr(" — minimizada") : "")
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
              dock.unexpose()
              if (app) dock.goToWindow(app, i)
            }
          }
        }
      }
    }
  }
}
