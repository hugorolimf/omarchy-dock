import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import qs.Commons as Commons

// Right-click menu.
Rectangle {
  id: menu
  required property var dock
  required property Item appCell
  visible: dock.menuIndex === appCell.index
  anchors.horizontalCenter: parent.horizontalCenter
  anchors.bottom: parent.top
  anchors.bottomMargin: 8
  width: 210
  height: menuCol.implicitHeight + 12
  radius: 10
  color: Commons.Color.menu.background
  border.width: 1
  border.color: Qt.rgba(Commons.Color.menu.text.r, Commons.Color.menu.text.g, Commons.Color.menu.text.b, 0.25)
  z: 10
  Column {
    id: menuCol
    anchors.fill: parent
    anchors.margins: 6
    spacing: 2
    Repeater {
      model: {
        var app = appCell.app
        var m = []
        // The app's windows by title, like macOS: ✓ the one in
        // focus, ◆ minimized ones.
        var act = dock.activeWindow(app)
        for (var wi = 0; wi < Math.min(app.windows.length, 6); wi++) {
          var pl = (app.places || [])[wi] || {}
          m.push({ t: app.windows[wi].title || app.name, a: "win", i: wi,
                   mark: wi === act ? "✓" : pl.minimized ? "◆" : "" })
        }
        if (app.windows.length > 1) m.push({ t: dock.tr("Mostrar todas as janelas"), a: "expose" })
        m = m.concat([
          { t: dock.tr("Abrir nova janela"), a: "new" },
          { t: app.pinned ? dock.tr("Desafixar da dock") : dock.tr("Fixar na dock"), a: "pin" }
        ])
        if (dock.cfg.moveMenu && app.windows.length > 0) {
          var only = app.workspaces.length === 1 ? app.workspaces[0] : -1
          for (var i = 0; i < dock.workspaceList.length; i++) {
            var w = dock.workspaceList[i]
            if (w.id !== only) m.push({ t: dock.tr("Mover para a área ") + w.name, a: "move", ws: String(w.id) })
          }
          m.push({ t: dock.tr("Mover para uma área nova"), a: "move", ws: "emptynm" })
        }
        if ((app.shown || []).length > 0) m.push({ t: dock.tr("Minimizar"), a: "min" })
        if ((app.minimized || []).length > 0) m.push({ t: dock.tr("Restaurar"), a: "restore" })
        m.push({ t: dock.tr("Fechar janelas"), a: "close", off: app.windows.length === 0 })
        m.push({ t: dock.tr("Encerrar app"), a: "quit", off: app.windows.length === 0 && !app.background })
        return m
      }
      delegate: Rectangle {
        required property var modelData
        visible: !modelData.off
        width: menuCol.width
        height: modelData.off ? 0 : 28
        radius: 6
        color: ma.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
        Text {
          textFormat: Text.PlainText
          visible: !!modelData.mark
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 8
          text: modelData.mark || ""
          color: Commons.Color.menu.text
          font.pixelSize: 11
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: modelData.a === "win" ? 24 : 8
          width: parent.width - anchors.leftMargin - 8
          elide: Text.ElideRight
          text: modelData.t
          color: Commons.Color.menu.text
          font.pixelSize: 13
          font.weight: modelData.a === "win" ? Font.Medium : Font.Normal
        }
        MouseArea {
          id: ma
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            var item = appCell.app
            dock.menuIndex = -1
            if (modelData.a === "win") dock.goToWindow(item, modelData.i)
            else if (modelData.a === "expose") dock.expose(appCell.key)
            else if (modelData.a === "new") dock.launch(item)
            else if (modelData.a === "pin") dock.togglePin(item)
            else if (modelData.a === "move") dock.moveToWorkspace(item, modelData.ws)
            else if (modelData.a === "min") dock.minimize(item)
            else if (modelData.a === "restore") dock.restore(item)
            else if (modelData.a === "quit") dock.quitApp(item)
            else for (var i = 0; i < item.windows.length; i++) item.windows[i].close()
          }
        }
      }
    }
  }
}
