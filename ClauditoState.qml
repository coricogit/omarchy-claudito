import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

import "code/hats.js" as Hats

// What Claude Code is doing right now. claudito-hook (run by Claude Code
// hooks) writes $XDG_RUNTIME_DIR/claudito/state.json; this follows the most
// recent session in it and works out the mode, hat and caption to show.
// Shared by the desktop buddy and the bar widget.
Item {
  id: root
  visible: false

  // Raw state from the hook.
  property string rawMode: "sleep"
  property string tool: ""
  property string detail: ""
  property string project: ""
  property real eventTs: 0
  property bool haveData: false

  // What is shown.
  property string mode: "sleep"
  property string hat: "nightcap"
  property real now: Date.now() / 1000
  property real thinkingSince: 0

  readonly property bool busy: toolModes.indexOf(mode) >= 0 || mode === "thinking"
  readonly property var toolModes: ["build", "terminal", "search", "explore", "lead", "plan", "create", "work"]

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + Quickshell.env("UID"))
  readonly property string statePath: runtimeDir + "/claudito/state.json"

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

  function readState(text) {
    if (!text) { haveData = false; return }
    try {
      var s = JSON.parse(text)
      var best = null
      var sessions = s && typeof s.sessions === "object" ? s.sessions : {}
      for (var id in sessions) {
        var v = sessions[id]
        if (v && typeof v.ts === "number" && (!best || v.ts > best.ts)) best = v
      }
      if (!best) { haveData = false; return }
      haveData = true
      if (best.ts !== eventTs) {
        tool = clean(best.tool, 40)
        detail = clean(best.detail, 60)
        project = clean(best.project, 60)
        rawMode = clean(best.mode, 20) || "idle"
        eventTs = best.ts
      }
    } catch (e) {
      // Half-written file: try again on the next read.
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readState(text())
    onLoadFailed: root.haveData = false
  }

  // The hook replaces the file atomically, and the folder may not exist until
  // Claude Code first runs, so re-read on a short timer as well.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: stateFile.reload()
  }

  // Ticks the clock and recomputes the shown mode.
  Timer {
    interval: 500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now() / 1000; root.update() }
  }

  onRawModeChanged: update()
  onEventTsChanged: update()
  onHaveDataChanged: update()

  function update() {
    var age = now - eventTs
    var next
    if (!haveData) next = "sleep"
    else if (rawMode === "done") next = age < 6 ? "done" : age < 600 ? "idle" : "sleep"
    else if (rawMode === "wake") next = age < 3 ? "wake" : age < 600 ? "idle" : "sleep"
    else if (rawMode === "oops") next = age < 3 ? "oops" : "thinking"
    else if (rawMode === "sleep") next = "sleep"
    else if (rawMode === "waiting") next = "waiting"
    // A tool that never reported back (Claude Code closed mid-task).
    else if (age > 900) next = "sleep"
    else next = rawMode

    // Short "thinking" gaps between tools keep the current hat on.
    if (next === "thinking" && toolModes.indexOf(mode) >= 0 && age < 1.5) return
    if (next === mode) return
    mode = next
    if (mode !== "waiting" && mode !== "oops") hat = Hats.hatFor(mode)
  }
}
