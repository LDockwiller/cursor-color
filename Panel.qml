import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Picker popup opened from the bar button. Every choice goes through the
// bundled `cursor-color` command, so the popup, the CLI and the menu entry
// share the same config file.
Panel {
  id: root
  moduleName: "io.github.ldockwiller.cursor-color"
  ipcTarget: "cursor-color"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string cli: root.pluginDir + "cursor-color"
  readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  property var config: ({ mode: "theme", theme_key: "accent", color: "#F25623", shape: "modern", style: "outline", recent: [] })
  property var themeColors: ({})
  property string hoverLabel: ""
  property string error: ""

  readonly property int panelWidth: Style.space(380)
  readonly property int swatchSize: Style.space(26)
  readonly property int gap: Style.space(7)

  // Theme keys offered under "Suivre le thème", in display order. Only the
  // ones the active theme's colors.toml defines are shown.
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

  readonly property var availableThemeKeys: root.themeKeys.filter(function(k) { return !!root.themeColors[k.key] })

  readonly property string currentColor: {
    if (root.config.mode === "fixed") return root.config.color
    if (root.config.mode === "off") return ""
    return root.themeColors[root.config.theme_key] || root.themeColors.accent || "#F25623"
  }

  // Color under the mouse / being dragged on the disk, before it's applied.
  readonly property string draftColor: root.colorHex(colorWheel.selectedColor)

  readonly property string statusText: {
    if (root.hoverLabel) return root.hoverLabel
    if (root.config.mode === "off") return "Curseur système par défaut"
    if (root.config.mode === "fixed") return "Couleur fixe · " + root.config.color
    var entry = root.themeKeys.filter(function(k) { return k.key === root.config.theme_key })[0]
    return "Suit le thème · " + (entry ? entry.label : root.config.theme_key) + " (" + root.currentColor + ")"
  }

  function open() {
    root.error = ""
    root.hoverLabel = ""
    hexField.text = ""
    colorsFile.reload()
    statusProcess.running = true
    root.controller.show()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
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

  function colorHex(c) {
    function part(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + part(c.r) + part(c.g) + part(c.b)
  }

  // Moves the disk marker and brightness bar onto `hex`.
  function showOnWheel(hex) {
    if (!hex) return
    var c = Qt.color(hex)
    if (c.hsvHue >= 0) colorWheel.hue = c.hsvHue
    colorWheel.saturation = c.hsvSaturation
    colorWheel.value = c.hsvValue
  }

  // Updates the local state right away so the selection moves without
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
    root.showOnWheel(color)
    root.setColor(color)
    keyCatcher.forceActiveFocus()
  }

  function pickFromScreen() {
    // Get the popup out of hyprpicker's way first.
    root.close()
    Quickshell.execDetached([root.cli, "pick"])
  }

  onCurrentColorChanged: if (!wheelMouseBusy.running) root.showOnWheel(root.currentColor)

  // Keeps a config refresh from yanking the marker while the user drags.
  Timer { id: wheelMouseBusy; interval: 800 }

  FileView {
    id: colorsFile
    path: root.colorsPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.themeColors = root.parseColors(text())
  }

  Process {
    id: statusProcess
    running: true
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
    border.width: swatch.selected ? 2 : (mouse.containsMouse ? 1 : 0)
    border.color: root.contentForeground

    Rectangle {
      anchors.fill: parent
      anchors.margins: 4
      radius: width / 2
      color: swatch.swatchColor
      border.width: 1
      border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.25)
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
    color: Qt.darker(root.contentForeground, 1.35)
    font.family: root.contentFontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.0
    font.capitalization: Font.AllUppercase
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.panelWidth)
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: hexField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(12)

        // Header: live preview + current mode.
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(12)

          Rectangle {
            Layout.preferredWidth: Style.space(36)
            Layout.preferredHeight: Style.space(36)
            radius: width / 2
            color: root.hoverLabel !== "" && root.hoverLabel.indexOf("#") >= 0
              ? root.hoverLabel.substring(root.hoverLabel.indexOf("#"), root.hoverLabel.indexOf("#") + 7)
              : (root.currentColor || "transparent")
            border.width: root.currentColor ? 1 : 2
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, root.currentColor ? 0.25 : 0.6)
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(2)
            Text {
              textFormat: Text.PlainText
              text: "Couleur du curseur"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: root.statusText
              color: root.contentForeground
              opacity: 0.7
              elide: Text.ElideRight
              font.family: root.contentFontFamily
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

        SectionLabel { text: "Couleur libre" }

        ColorWheel {
          id: colorWheel
          Layout.alignment: Qt.AlignHCenter
          Layout.preferredWidth: Style.space(220)
          Layout.preferredHeight: Style.space(220)
          borderColor: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
          onHovered: function(c) { root.hoverLabel = "Aperçu · " + root.colorHex(c) }
          onHoverEnded: if (root.hoverLabel.indexOf("Aperçu · ") === 0) root.hoverLabel = ""
          onMoved: {
            wheelMouseBusy.restart()
            root.hoverLabel = "Aperçu · " + root.draftColor
          }
          onCommitted: {
            wheelMouseBusy.restart()
            root.setColor(root.draftColor)
          }
        }

        // Brightness (HSV value) for the disk.
        Item {
          id: brightness
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(18)

          Rectangle {
            anchors.fill: parent
            anchors.topMargin: Style.space(3)
            anchors.bottomMargin: Style.space(3)
            radius: height / 2
            border.width: 1
            border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.3)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "#000000" }
              GradientStop { position: 1; color: Qt.hsva(colorWheel.hue, colorWheel.saturation, 1, 1) }
            }
          }

          Rectangle {
            width: parent.height
            height: parent.height
            radius: width / 2
            x: colorWheel.value * (brightness.width - width)
            color: colorWheel.selectedColor
            border.width: 2
            border.color: root.contentForeground
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            preventStealing: true
            function setFrom(mouse) {
              wheelMouseBusy.restart()
              colorWheel.value = Math.max(0, Math.min(1, mouse.x / brightness.width))
              root.hoverLabel = "Aperçu · " + root.draftColor
            }
            onPressed: function(mouse) { setFrom(mouse) }
            onPositionChanged: function(mouse) { if (pressed) setFrom(mouse) }
            onReleased: {
              root.hoverLabel = ""
              root.setColor(root.draftColor)
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: root.gap

          TextField {
            id: hexField
            Layout.fillWidth: true
            placeholderText: root.draftColor
            maximumLength: 7
            onTextChanged: {
              var c = root.normalizeHex(text)
              if (c.length === 7 && text.replace("#", "").length === 6) root.showOnWheel(c)
            }
            onAccepted: root.applyHex()
            Keys.onEscapePressed: keyCatcher.forceActiveFocus()
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
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
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
              onPicked: {
                root.showOnWheel(modelData)
                root.setColor(modelData)
              }
            }
          }
        }

        SectionLabel { text: "Apparence" }
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

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
