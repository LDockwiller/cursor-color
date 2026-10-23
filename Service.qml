import QtQuick
import Quickshell
import Quickshell.Io

// No UI: keeps the cursor in sync with the active theme. The shell mounts
// this once per session (keepLoaded), so it applies the saved settings at
// login / shell restart, then watches the theme's colors.toml and re-applies
// whenever `omarchy theme set` swaps it. No theme-set or post-boot hook is
// needed for that. recolor.py skips the rebuild when the resolved colors
// didn't change, so a fixed color only costs a `hyprctl setcursor`.
Item {
  id: root

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string colorsPath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
  property bool pending: false

  function apply() {
    if (applyProcess.running) {
      root.pending = true
      return
    }
    applyProcess.running = true
  }

  Component.onCompleted: debounce.restart()

  // A theme switch rewrites the whole theme directory; wait for it to settle.
  Timer {
    id: debounce
    interval: 400
    onTriggered: root.apply()
  }

  FileView {
    path: root.colorsPath
    watchChanges: true
    onFileChanged: reload()
    onLoaded: debounce.restart()
  }

  Process {
    id: applyProcess
    running: false
    command: ["python3", root.pluginDir + "recolor.py"]
    stdout: StdioCollector { onStreamFinished: if (text) console.log(text.trim()) }
    stderr: StdioCollector { onStreamFinished: if (text) console.warn("cursor-color:", text.trim()) }
    onExited: {
      if (root.pending) {
        root.pending = false
        root.apply()
      }
    }
  }
}
