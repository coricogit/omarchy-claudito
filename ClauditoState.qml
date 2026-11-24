import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

import "code/hats.js" as Hats

// What Claude Code is doing right now. claudito-watch, run by Buddy.qml, picks
// the session to show and its mode and writes them to
// $XDG_RUNTIME_DIR/claudito/view.json; this reads that file and works out the
// hat and caption. Shared by the desktop buddy and the bar widget.
Item {
  id: root
  visible: false

  property string mode: "sleep"
  property string hat: "nightcap"
  property string tool: ""
  property string detail: ""
  property string project: ""
  // The season where you live, "" until it is known.
  property string season: ""

  readonly property bool busy: toolModes.indexOf(mode) >= 0 || mode === "thinking"
  readonly property var toolModes: ["build", "terminal", "search", "explore", "lead", "plan", "create", "work"]

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))
  readonly property string viewPath: runtimeDir + "/claudito/view.json"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // Hook text is untrusted: keep it short and on one line.
  function clean(value, limit) {
    var text = String(value || "").replace(/\s+/g, " ").trim()
    return text.length > limit ? text.slice(0, limit - 1) + "…" : text
  }

  readonly property string label: {
    var d = detail
    switch (mode) {
    case "wake": return strings.t("mode.wake")
    case "thinking": return strings.t("mode.thinking")
    case "build": return d ? strings.t("mode.build").arg(d) : strings.t("mode.buildPlain")
    case "terminal": return d ? strings.t("mode.terminal").arg(d) : strings.t("mode.terminalPlain")
    case "search": return d ? strings.t("mode.search").arg(d) : strings.t("mode.searchPlain")
    case "explore": return d ? strings.t("mode.explore").arg(d) : strings.t("mode.explorePlain")
    case "lead": return d ? strings.t("mode.lead").arg(d) : strings.t("mode.leadPlain")
    case "plan": return strings.t("mode.plan")
    case "create": return d ? strings.t("mode.create").arg(d) : strings.t("mode.createPlain")
    case "work": return tool ? strings.t("mode.work").arg(tool) : strings.t("mode.workPlain")
    case "waiting": return strings.t("mode.waiting")
    case "oops": return strings.t("mode.oops")
    case "done": return strings.t("mode.done")
    case "idle": return strings.t("mode.idle")
    default: return strings.t("mode.sleep")
    }
  }

  function readView(text) {
    var v
    try {
      v = JSON.parse(text)
    } catch (e) {
      return   // try again on the next read
    }
    if (!v || typeof v !== "object") return
    tool = clean(v.tool, 40)
    detail = clean(v.detail, 60)
    project = clean(v.project, 60)
    season = clean(v.season, 10)
    show(clean(v.mode, 20) || "sleep")
  }

  function show(next) {
    if (next === mode) return
    mode = next
    if (mode !== "waiting" && mode !== "oops") hat = Hats.hatFor(mode)
  }

  FileView {
    id: viewFile
    path: root.viewPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readView(text())
    onLoadFailed: root.show("sleep")
  }

  // The file is replaced atomically, and may not exist yet, so re-read it on a
  // short timer as well.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: viewFile.reload()
  }
}
