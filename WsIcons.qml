import QtQuick
import qs.Commons as Commons

// A workspace tile's icons: one per window on it, loose (two and "+N" past
// three); windows minimized from there are dimmed; an empty one shows a ring.
Row {
  id: icons
  required property var dock
  required property var ws
  property int size: 18
  property bool bright: false
  readonly property color ink: Commons.Color.menu.text
  height: size
  spacing: 3

  // One per window, so an app with two windows shows twice; "~app": a
  // window minimized from here.
  readonly property var apps: icons.ws.apps.concat((icons.ws.minApps || []).map(function(a) { return "~" + a }))
  readonly property int shown: apps.length > 3 ? 2 : apps.length

  Rectangle {
    visible: icons.apps.length === 0
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(icons.size * 0.45)
    height: width
    radius: width / 2
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(icons.ink.r, icons.ink.g, icons.ink.b, 0.3)
  }
  Repeater {
    model: icons.apps.slice(0, icons.shown)
    Image {
      required property var modelData
      readonly property bool down: String(modelData).charAt(0) === "~"
      width: icons.size
      height: width
      opacity: (down ? 0.35 : 1) * (icons.bright ? 1 : 0.8)
      property var iconList: icons.dock.iconCandidates(down ? String(modelData).slice(1) : modelData)
      property int iconTry: 0
      onIconListChanged: iconTry = 0
      source: icons.dock.iconFor(iconList, iconTry)
      onStatusChanged: if (status === Image.Error) Qt.callLater(() => iconTry++)
      sourceSize: Qt.size(128, 128)
      smooth: true
      mipmap: true
      fillMode: Image.PreserveAspectFit
      // Pops in when a window lands on this workspace.
      scale: icons.dock.ready ? 0.4 : 1
      Component.onCompleted: scale = 1
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
    }
  }
  Text {
    textFormat: Text.PlainText
    visible: icons.apps.length > 3
    height: icons.size
    verticalAlignment: Text.AlignVCenter
    text: "+" + (icons.apps.length - 2)
    color: icons.ink
    opacity: 0.7
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: Math.round(icons.size * 0.5)
  }
}
