import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// Minimized windows, like macOS: a thumbnail of each at the right end of
// the dock, its app's icon in the corner. Click one to bring it back.
Row {
  required property var dock
  visible: dock.cfg.showMinimized && dock.minModel.count > 0
  anchors.bottom: parent.bottom
  leftPadding: dock.spacing
  spacing: 0

  Repeater {
    model: dock.minModel
    // Opens room, then pops in (and the other way round), like the workspace tiles.
    delegate: Item {
      id: mcell
      required property string key
      readonly property var entry: dock.minMap[key] || ({})
      readonly property var toplevel: entry.toplevel || null
      property real open: 0
      property real pop: 0
      readonly property bool going: dock.minClosing[key] !== undefined
      SequentialAnimation {
        id: mAppear
        NumberAnimation { target: mcell; property: "open"; to: 1; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { target: mcell; property: "pop"; to: 1; duration: 220; easing.type: Easing.OutBack }
      }
      SequentialAnimation {
        id: mVanish
        NumberAnimation { target: mcell; property: "pop"; to: 0; duration: 90; easing.type: Easing.InCubic }
        NumberAnimation { target: mcell; property: "open"; to: 0; duration: 120; easing.type: Easing.InOutCubic }
      }
      function settle() {
        if (going) { mAppear.stop(); mVanish.start() }
        else { mVanish.stop(); if (open < 1 || pop < 1) mAppear.start() }
      }
      Component.onCompleted: {
        if (!dock.ready && !going) { open = 1; pop = 1 }
        settle()
      }
      onGoingChanged: settle()
      width: dock.slot * open
      height: dock.baseSize

      Item {
        id: mtile
        width: dock.baseSize
        height: dock.baseSize
        scale: mcell.pop * (mMouse.containsMouse ? 1.08 : 1)
        opacity: mcell.pop
        transformOrigin: Item.Bottom
        Behavior on scale { enabled: mcell.pop === 1; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // One frame of the window (it doesn't change while down);
        // taken again when the pointer comes by.
        Item {
          anchors.fill: parent
          anchors.margins: Math.round(dock.baseSize * 0.04)
          // Translucent windows (the terminal) show the wallpaper
          // through, as on the desktop, instead of a black box.
          Image {
            anchors.fill: mview
            visible: mview.hasContent
            source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
            sourceSize: Qt.size(48, 30)
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
          }
          ScreencopyView {
            id: mview
            readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 16 / 10
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * aspect)
            height: Math.min(parent.height, parent.width / aspect)
            captureSource: mcell.toplevel
            live: false
            paintCursor: false
            constraintSize: Qt.size(width * 2, height * 2)
            visible: hasContent
            layer.enabled: true
            layer.smooth: true
          }
          Rectangle {
            anchors.fill: mview
            visible: mview.hasContent
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, mMouse.containsMouse ? 0.5 : 0.22)
          }
        }

        // The app it belongs to, in the corner (alone until a frame arrives).
        Image {
          readonly property bool alone: !mview.hasContent
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: alone ? (parent.width - width) / 2 : -2
          anchors.bottomMargin: alone ? (parent.height - height) / 2 : -2
          width: Math.round(dock.baseSize * (alone ? 0.7 : 0.42))
          height: width
          property var iconList: dock.iconCandidates(mcell.entry.appId)
          property int iconTry: 0
          onIconListChanged: iconTry = 0
          source: dock.iconFor(iconList, iconTry)
          onStatusChanged: if (status === Image.Error) Qt.callLater(() => iconTry++)
          sourceSize: Qt.size(128, 128)
          smooth: true
          mipmap: true
          fillMode: Image.PreserveAspectFit
        }

        // The window's title above it.
        Rectangle {
          visible: mMouse.containsMouse && dock.menuIndex < 0 && dock.fanKey === "" && dock.dragKey === ""
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.top
          anchors.bottomMargin: 8
          width: Math.min(360, mlabel.implicitWidth + 16)
          height: mlabel.implicitHeight + 8
          radius: 8
          color: Commons.Color.menu.background
          border.width: 1
          border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.2)
          Text {
            id: mlabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            width: Math.min(implicitWidth, 360 - 16)
            elide: Text.ElideRight
            text: (mcell.toplevel && mcell.toplevel.title) || (dock.entryFor(mcell.entry.appId) || {}).name || mcell.entry.appId || ""
            color: Commons.Color.menu.text
            font.pixelSize: 13
          }
        }

        MouseArea {
          id: mMouse
          anchors.fill: parent
          hoverEnabled: true
          onContainsMouseChanged: if (containsMouse) mview.captureFrame()
          onClicked: { dock.menuIndex = -1; dock.restoreAddress(mcell.key) }
        }
      }
    }
  }
}
