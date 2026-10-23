import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button: a cursor glyph tinted with the current cursor color. Clicking it
// opens the picker popup (Panel.qml), like the other bar widgets' panels.
// `cursor-color open` reaches open() through `omarchy-shell shell summon`.
BarWidget {
  id: root
  moduleName: "io.github.ldockwiller.cursor-color"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string currentColor: panelLoader.item ? panelLoader.item.currentColor : ""

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "cursor-color"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF01C0)
    foreground: root.currentColor !== "" ? root.currentColor : (root.bar ? root.bar.foreground : Color.foreground)
    tooltipText: "Couleur du curseur"
    onPressed: function(b) { root.togglePanel() }
  }
}
