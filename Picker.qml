import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Palette picker, summoned with `cursor-color open` (or
// `omarchy-shell shell summon io.github.ldockwiller.cursor-color '{}'`).
// Every choice goes through the bundled `cursor-color` command, so the
// picker, the CLI and the menu entry share the same config file.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string cli: root.pluginDir + "cursor-color"
  readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  property bool opened: false
  property var config: ({ mode: "theme", theme_key: "accent", color: "#F25623", shape: "modern", style: "outline", recent: [] })
  property var themeColors: ({})
  property string hoverLabel: ""
  property string error: ""

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int swatchSize: Style.space(30)
  readonly property int gap: Style.space(8)

  // Theme keys offered under "Thème", in display order. Only the ones the
  // active theme's colors.toml defines are shown.
  readonly property var themeKeys: [
    { key: "accent", label: "Accent" },
    { key: "cursor", label: "Curseur du terminal" },
    { key: "foreground", label: "Texte" },
    { key: "red", label: "Rouge" },
    { key: "orange", label: "Orange" },
    { key: "yellow", label: "Jaune" },
    { key: "green", label: "Vert" },
    { key: "cyan", label: "Cyan" },
    { key: "blue", label: "Bleu" },
    { key: "magenta", label: "Magenta" },
    { key: "brown", label: "Brun" }
  ]

  readonly property var palette: [
    { color: "#ffffff", label: "Blanc" },
    { color: "#c0c0c0", label: "Argent" },
    { color: "#000000", label: "Noir" },
    { color: "#ff5555", label: "Rouge" },
    { color: "#ff9e3b", label: "Orange" },
    { color: "#ffd75f", label: "Jaune" },
    { color: "#a6e22e", label: "Lime" },
    { color: "#39ff14", label: "Vert néon" },
    { color: "#50fa7b", label: "Vert" },
    { color: "#2ec4b6", label: "Turquoise" },
    { color: "#8be9fd", label: "Cyan" },
    { color: "#4f8cff", label: "Bleu" },
    { color: "#7c5cff", label: "Indigo" },
    { color: "#bd93f9", label: "Violet" },
    { color: "#ff79c6", label: "Rose" },
    { color: "#ff2d95", label: "Magenta" }
  ]

  readonly property var availableThemeKeys: root.themeKeys.filter(function(k) { return !!root.themeColors[k.key] })

  readonly property string currentColor: {
    if (root.config.mode === "fixed") return root.config.color
    if (root.config.mode === "off") return ""
    return root.themeColors[root.config.theme_key] || root.themeColors.accent || "#F25623"
  }

  readonly property string statusText: {
    if (root.hoverLabel) return root.hoverLabel
    if (root.config.mode === "off") return "Curseur système par défaut"
    if (root.config.mode === "fixed") return "Couleur fixe · " + root.config.color
    var entry = root.themeKeys.filter(function(k) { return k.key === root.config.theme_key })[0]
    return "Suit le thème · " + (entry ? entry.label : root.config.theme_key) + " (" + root.currentColor + ")"
  }

  function open(payloadJson) {
    root.opened = true
    root.error = ""
    root.hoverLabel = ""
    hexField.text = ""
    colorsFile.reload()
    statusProcess.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.ldockwiller.cursor-color")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function parseColors(text) {
    var out = ({})
    var re = /^\s*([a-z_]+)\s*=\s*["']?(#[0-9a-fA-F]{6})["']?/gm
    var m
    while ((m = re.exec(text)) !== null) out[m[1]] = m[2].toLowerCase()
    return out
  }

  function normalizeHex(value) {
    var c = String(value || "").trim().replace(/^#/, "").toLowerCase()
    if (/^[0-9a-f]{3}$/.test(c)) c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
    return /^[0-9a-f]{6}$/.test(c) ? "#" + c : ""
  }

  // Updates the local state right away so the selection ring moves without
  // waiting for the rebuild, then runs the command and re-reads the config.
  function run(args, optimistic) {
    if (optimistic) {
      var next = ({})
      for (var k in root.config) next[k] = root.config[k]
      for (var o in optimistic) next[o] = optimistic[o]
      root.config = next
    }
    root.error = ""
    actionProcess.command = [root.cli].concat(args)
    actionProcess.running = true
  }

  function followTheme(key) { run(["theme", key], { mode: "theme", theme_key: key }) }
  function setColor(color) { run(["set", color], { mode: "fixed", color: color }) }

  function applyHex() {
    var color = root.normalizeHex(hexField.text)
    if (!color) {
      root.error = "Code invalide, attendu #rrggbb"
      return
    }
    hexField.text = ""
    root.setColor(color)
    keyCatcher.forceActiveFocus()
  }

  function pickFromScreen() {
    // The overlay covers the screen, so get out of hyprpicker's way first.
    root.dismiss()
    Quickshell.execDetached([root.cli, "pick"])
  }

  FileView {
    id: colorsFile
    path: root.colorsPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.themeColors = root.parseColors(text())
  }

  Process {
    id: statusProcess
    running: false
    command: [root.cli, "status"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.config = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    stderr: StdioCollector { onStreamFinished: if (text) root.error = text.trim() }
    onExited: statusProcess.running = true
  }

  component Swatch: Rectangle {
    id: swatch
    property string swatchColor: "#000000"
    property string label: ""
    property bool selected: false
    signal picked()

    width: root.swatchSize
    height: root.swatchSize
    radius: width / 2
    color: "transparent"
    border.width: swatch.selected ? Math.max(2, Style.space(2)) : (mouse.containsMouse ? 1 : 0)
    border.color: root.foreground

    Rectangle {
      anchors.fill: parent
      anchors.margins: Math.max(3, Style.space(4))
      radius: width / 2
      color: swatch.swatchColor
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.hoverLabel = swatch.label + " · " + swatch.swatchColor
      onExited: if (root.hoverLabel.indexOf(swatch.label + " · ") === 0) root.hoverLabel = ""
      onClicked: swatch.picked()
    }
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 1
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-cursor-color"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }
      }

      ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.space(14)

        // Header: live preview + current mode.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Rectangle {
            Layout.preferredWidth: Style.space(40)
            Layout.preferredHeight: Style.space(40)
            radius: width / 2
            color: root.currentColor || "transparent"
            border.width: root.currentColor ? 1 : Math.max(2, Style.space(2))
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, root.currentColor ? 0.25 : 0.6)
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: "Couleur du curseur"
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.statusText
              color: root.foreground
              opacity: 0.7
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        SectionLabel { text: "Suivre le thème" }
        Flow {
          Layout.fillWidth: true
          spacing: root.gap
          Repeater {
            model: root.availableThemeKeys
            delegate: Swatch {
              required property var modelData
              swatchColor: root.themeColors[modelData.key]
              label: modelData.label
              selected: root.config.mode === "theme" && root.config.theme_key === modelData.key
              onPicked: root.followTheme(modelData.key)
            }
          }
        }

        SectionLabel { text: "Palette" }
        Flow {
          Layout.fillWidth: true
          spacing: root.gap
          Repeater {
            model: root.palette
            delegate: Swatch {
              required property var modelData
              swatchColor: modelData.color
              label: modelData.label
              selected: root.config.mode === "fixed" && String(root.config.color).toLowerCase() === modelData.color
              onPicked: root.setColor(modelData.color)
            }
          }
        }

        SectionLabel {
          text: "Récentes"
          visible: (root.config.recent || []).length > 0
        }
        Flow {
          Layout.fillWidth: true
          spacing: root.gap
          visible: (root.config.recent || []).length > 0
          Repeater {
            model: root.config.recent || []
            delegate: Swatch {
              required property var modelData
              swatchColor: modelData
              label: "Récente"
              selected: root.config.mode === "fixed" && String(root.config.color).toLowerCase() === String(modelData).toLowerCase()
              onPicked: root.setColor(modelData)
            }
          }
        }

        SectionLabel { text: "Code couleur" }
        RowLayout {
          Layout.fillWidth: true
          spacing: root.gap

          Rectangle {
            Layout.preferredWidth: Style.space(28)
            Layout.preferredHeight: Style.space(28)
            radius: width / 2
            color: root.normalizeHex(hexField.text) || "transparent"
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
          }

          TextField {
            id: hexField
            Layout.fillWidth: true
            placeholderText: "#rrggbb"
            maximumLength: 7
            onAccepted: root.applyHex()
            Keys.onEscapePressed: root.dismiss()
          }

          Button {
            text: "Appliquer"
            bordered: true
            onClicked: root.applyHex()
          }

          Button {
            iconText: String.fromCodePoint(0xF020A)
            tooltipText: "Prendre une couleur à l'écran"
            bordered: true
            onClicked: root.pickFromScreen()
          }
        }

        Text {
          Layout.fillWidth: true
          visible: root.error !== ""
          textFormat: Text.PlainText
          text: root.error
          color: Commons.Color.urgent
          wrapMode: Text.Wrap
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        SectionLabel { text: "Apparence" }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          ButtonGroup {
            options: [{ value: "modern", label: "Arrondi" }, { value: "original", label: "Pointu" }]
            value: root.config.shape
            onChanged: function(value) { root.run(["shape", value], { shape: value }) }
          }

          ButtonGroup {
            options: [{ value: "outline", label: "Contour" }, { value: "filled", label: "Rempli" }]
            value: root.config.style
            onChanged: function(value) { root.run(["style", value], { style: value }) }
          }
        }

        Button {
          Layout.fillWidth: true
          text: "Utiliser le curseur système"
          bordered: true
          selected: root.config.mode === "off"
          onClicked: root.run(["default"], { mode: "off" })
        }
      }
    }
  }
}
