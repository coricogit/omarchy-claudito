import QtQuick
import Quickshell
import Quickshell.Io

// Desktop buddy settings, shared by the service (which draws the buddy) and
// the bar panel (which changes them). Kept in
// ~/.local/state/claudito/omarchy.json so both see every change.
Item {
  id: root
  visible: false

  readonly property var corners: ["top-left", "top-right", "bottom-left", "bottom-right"]
  readonly property var sizes: ["small", "medium", "large"]

  property bool buddy: true
  property bool onTop: false
  property string corner: "bottom-right"
  property string size: "medium"
  // Screen name (e.g. DP-1); empty means the first screen.
  property string monitor: ""
  property bool loaded: false

  readonly property string dir: Quickshell.env("HOME") + "/.local/state/claudito"
  readonly property string path: dir + "/omarchy.json"

  function apply(text) {
    var s = {}
    try { s = JSON.parse(text || "{}") || {} } catch (e) { s = {} }
    buddy = s.buddy !== false
    onTop = s.onTop === true
    corner = corners.indexOf(s.corner) >= 0 ? s.corner : "bottom-right"
    size = sizes.indexOf(s.size) >= 0 ? s.size : "medium"
    monitor = typeof s.monitor === "string" ? s.monitor.slice(0, 64) : ""
    loaded = true
  }

  function set(name, value) {
    var next = { buddy: buddy, onTop: onTop, corner: corner, size: size, monitor: monitor }
    next[name] = value
    apply(JSON.stringify(next))
    writer.command = ["sh", "-c", 'mkdir -p -m 700 "$1" && t="$(mktemp "$3.XXXXXX")" && printf "%s\\n" "$2" > "$t" && mv -f "$t" "$3"',
                      "claudito", dir, JSON.stringify(next), path]
    writer.running = true
  }

  Process { id: writer }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.apply(text())
    onLoadFailed: root.apply("{}")
  }

  // The file is replaced atomically, which can drop the watch.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: file.reload()
  }
}
