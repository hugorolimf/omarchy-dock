import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar button + popup with the dock's settings. Values are written through
// DockSettings, which the dock watches, so changes apply live.
Panel {
  id: root

  // Portuguese is the source language; anything else gets English.
  readonly property bool portuguese: Qt.locale().name.indexOf("pt") === 0
  readonly property var english: ({"Comportamento": "Behavior", "Áreas": "Workspaces", "Aparência": "Look", "Ocultar automaticamente": "Hide automatically", "Como no macOS: a dock some e volta quando o mouse encosta na borda inferior. Desligado, ela fica sempre visível.": "Like macOS: the dock hides and comes back when the pointer touches the bottom edge. Off, it always stays visible.", "Atraso para aparecer": "Reveal delay", "Compacta sem o mouse": "Compact without the pointer", "A dock encolhe quando o mouse sai e volta ao tamanho normal quando ele chega.": "The dock shrinks when the pointer leaves and grows back when it arrives.", "Ampliar ao passar o mouse": "Magnify on hover", "Mostrar áreas de trabalho": "Show workspaces", "No lado direito da dock: cada área com os ícones das suas janelas. Clique para trocar, role para passar de uma a outra.": "On the right of the dock: each workspace with its windows' icons. Click to switch, scroll to step through them.", "Número da área no ícone": "Workspace number on icons", "Mostra em qual área estão as janelas de um app quando elas não estão na área atual.": "Shows which workspace an app's windows are on when they are not on the current one.", "Mover para outra área no menu": "Move to workspace in the menu", "O botão direito no ícone ganha \"Mover para a área N\".": "Right-clicking an icon adds \"Move to workspace N\".", "Só apps deste monitor": "Only apps on this monitor", "Cada monitor tem sua dock; além dos fixados, ela mostra apenas os apps com janela naquele monitor.": "Every monitor has its own dock; besides pinned apps, it shows only apps with a window on that monitor.", "Só apps desta área": "Only apps on this workspace", "Além dos fixados, a dock mostra apenas os apps com janela na área atual.": "Besides pinned apps, the dock shows only apps with a window on the current workspace.", "Tamanho dos ícones": "Icon size", "Tamanho compacto": "Compact size", "Ampliação": "Magnification", "Opacidade do fundo": "Background opacity", "Vidro do plugin Liquid Glass atrás da dock. Ao ligar, o fundo fica mais transparente para o vidro aparecer.": "Glass from the Liquid Glass plugin behind the dock. Turning it on makes the plate more transparent so the glass shows."})
  function tr(text) { return portuguese ? text : (english[text] || text) }
  moduleName: "io.github.hugorolimf.dock"
  ipcTarget: "io.github.hugorolimf.dock"

  DockSettings { id: settings }
  readonly property var cfg: settings.values
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Glass on a layer surface is Hyprland config (hyprglass only commits
  // layer() calls on a config reload), so it lives in an Omarchy toggle file
  // that hypr/toggles.lua loads on every reload.
  readonly property string glassToggle: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/toggles/hypr/hugorolimf-dock-glass.lua"
  readonly property string glassLua: [
    "-- io.github.hugorolimf.dock: Liquid Glass on the dock. Written by the dock's bar panel; turn it off there.",
    "if hl.plugin.hyprglass then",
    "  hl.plugin.hyprglass.config({ layers = { enabled = true, namespaces = \"omarchy-dock\" } })",
    "  hl.plugin.hyprglass.layer(\"omarchy-dock\", { mask_threshold = 0.05, live_resample = false })",
    "end"
  ].join("\n")

  function setGlass(on) {
    cfg.liquidGlass = on
    // The glass shows through the plate; a near-opaque plate would hide it.
    if (on && cfg.opacity > 0.4) cfg.opacity = 0.25
    if (on) Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1" && hyprctl reload', "sh", glassToggle, glassLua])
    else Quickshell.execDetached(["sh", "-c", 'rm -f "$1" && hyprctl reload', "sh", glassToggle])
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF10A9)
    tooltipText: "Dock"
    onPressed: function(b) { root.toggle() }
  }

  // Settings are split in tabs, like macOS System Settings, so the panel
  // stays short; a page taller than the screen still scrolls.
  property string tab: "behavior"

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Text {
          id: title
          text: "Dock"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        ButtonGroup {
          id: tabs
          options: [
            { value: "behavior", label: root.tr("Comportamento") },
            { value: "workspaces", label: root.tr("Áreas") },
            { value: "look", label: root.tr("Aparência") }
          ]
          value: root.tab
          foreground: root.fg
          accent: Commons.Color.accent
          fontFamily: root.fontFamily
          onChanged: function(v) { root.tab = v; flick.contentY = 0 }
        }

        Flickable {
          id: flick
          width: parent.width
          // Whatever the screen leaves below the title and the tabs.
          readonly property real room: panel.availableCardHeight - panel.verticalContentInset
            - title.height - tabs.height - column.spacing * 2
          height: Math.min(page.implicitHeight, Math.max(Style.space(120), room))
          contentHeight: page.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: page
            width: flick.width
            spacing: Style.space(10)

            Column {
              visible: root.tab === "behavior"
              width: parent.width
              spacing: Style.space(10)

              DockToggle {
                label: root.tr("Ocultar automaticamente")
                description: root.tr("Como no macOS: a dock some e volta quando o mouse encosta na borda inferior. Desligado, ela fica sempre visível.")
                checked: root.cfg.autoHide
                onClicked: root.cfg.autoHide = !root.cfg.autoHide
              }
              DockSlider {
                label: root.tr("Atraso para aparecer")
                enabled: root.cfg.autoHide
                opacity: enabled ? 1 : 0.45
                minimum: 0; maximum: 1; step: 0.05
                value: root.cfg.revealDelay
                format: function(v) { return v.toFixed(2) + " s" }
                onCommit: function(v) { root.cfg.revealDelay = Math.round(v * 100) / 100 }
              }
              DockToggle {
                label: root.tr("Compacta sem o mouse")
                description: root.tr("A dock encolhe quando o mouse sai e volta ao tamanho normal quando ele chega.")
                enabled: !root.cfg.autoHide
                opacity: enabled ? 1 : 0.45
                checked: root.cfg.compact
                onClicked: root.cfg.compact = !root.cfg.compact
              }
              DockToggle {
                label: root.tr("Ampliar ao passar o mouse")
                checked: root.cfg.magnify
                onClicked: root.cfg.magnify = !root.cfg.magnify
              }
            }

            Column {
              visible: root.tab === "workspaces"
              width: parent.width
              spacing: Style.space(10)

              DockToggle {
                label: root.tr("Mostrar áreas de trabalho")
                description: root.tr("No lado direito da dock: cada área com os ícones das suas janelas. Clique para trocar, role para passar de uma a outra.")
                checked: root.cfg.showWorkspaces
                onClicked: root.cfg.showWorkspaces = !root.cfg.showWorkspaces
              }
              DockToggle {
                label: root.tr("Número da área no ícone")
                description: root.tr("Mostra em qual área estão as janelas de um app quando elas não estão na área atual.")
                checked: root.cfg.workspaceBadges
                onClicked: root.cfg.workspaceBadges = !root.cfg.workspaceBadges
              }
              DockToggle {
                label: root.tr("Mover para outra área no menu")
                description: root.tr("O botão direito no ícone ganha \"Mover para a área N\".")
                checked: root.cfg.moveMenu
                onClicked: root.cfg.moveMenu = !root.cfg.moveMenu
              }
              DockToggle {
                label: root.tr("Só apps deste monitor")
                description: root.tr("Cada monitor tem sua dock; além dos fixados, ela mostra apenas os apps com janela naquele monitor.")
                checked: root.cfg.monitorAppsOnly
                onClicked: root.cfg.monitorAppsOnly = !root.cfg.monitorAppsOnly
              }
              DockToggle {
                label: root.tr("Só apps desta área")
                description: root.tr("Além dos fixados, a dock mostra apenas os apps com janela na área atual.")
                checked: root.cfg.currentWorkspaceOnly
                onClicked: root.cfg.currentWorkspaceOnly = !root.cfg.currentWorkspaceOnly
              }
            }

            Column {
              visible: root.tab === "look"
              width: parent.width
              spacing: Style.space(10)

              DockSlider {
                label: root.tr("Tamanho dos ícones")
                minimum: 32; maximum: 96; step: 2; integer: true
                value: root.cfg.iconSize
                format: function(v) { return Math.round(v) + " px" }
                onCommit: function(v) { root.cfg.iconSize = Math.round(v) }
              }
              DockSlider {
                label: root.tr("Tamanho compacto")
                enabled: root.cfg.compact && !root.cfg.autoHide
                opacity: enabled ? 1 : 0.45
                minimum: 0.4; maximum: 0.9; step: 0.05
                value: root.cfg.compactScale
                format: function(v) { return Math.round(v * 100) + "%" }
                onCommit: function(v) { root.cfg.compactScale = Math.round(v * 100) / 100 }
              }
              DockSlider {
                label: root.tr("Ampliação")
                enabled: root.cfg.magnify
                opacity: enabled ? 1 : 0.45
                minimum: 1.2; maximum: 2.4; step: 0.1
                value: root.cfg.maxScale
                format: function(v) { return v.toFixed(1) + "×" }
                onCommit: function(v) { root.cfg.maxScale = Math.round(v * 10) / 10 }
              }
              DockSlider {
                label: root.tr("Opacidade do fundo")
                minimum: 0; maximum: 1; step: 0.05
                value: root.cfg.opacity
                format: function(v) { return Math.round(v * 100) + "%" }
                onCommit: function(v) { root.cfg.opacity = Math.round(v * 100) / 100 }
              }
              DockToggle {
                label: "Liquid Glass"
                description: root.tr("Vidro do plugin Liquid Glass atrás da dock. Ao ligar, o fundo fica mais transparente para o vidro aparecer.")
                checked: root.cfg.liquidGlass
                onClicked: root.setGlass(!root.cfg.liquidGlass)
              }
            }
          }
        }
      }
    }
  }

  component DockToggle: Toggle {
    width: parent.width
    foreground: root.fg
    accent: Commons.Color.accent
    fontFamily: root.fontFamily
  }

  // Label + value on one line, slider below. Writes only on release so a
  // drag doesn't rewrite settings.json on every pixel.
  component DockSlider: Column {
    id: ds
    property string label: ""
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property bool integer: false
    property var format: function(v) { return String(v) }
    signal commit(real v)

    width: parent.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: dsLabel.implicitHeight
      Text {
        id: dsLabel
        text: ds.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.right: parent.right
        text: ds.format(dsSlider.dragging ? dsSlider.liveValue : ds.value)
        color: root.fg
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
    PanelSlider {
      id: dsSlider
      bar: root.bar
      width: parent.width
      minimum: ds.minimum
      maximum: ds.maximum
      step: ds.step
      integer: ds.integer
      value: ds.value
      onReleased: function(v) { ds.commit(v) }
    }
  }
}
