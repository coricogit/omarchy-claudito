import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

import "code/plain.js" as Plain
import "ui"

// Claudito on the desktop: a small layer-shell window in a corner of the
// chosen screen (the first one unless picked in the bar panel), or of every
// screen. It sits under your windows like a desktop widget, or above
// them if you turn that on in the bar panel. Only the buddy itself takes
// clicks (to poke it); the rest of the window lets them through.
Scope {
  id: root

  property var shell: null
  property var manifest: null

  ClauditoState { id: claude }
  BuddySettings { id: settings }
  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string season: settings.seasonFor(claude.season)

  // ---------- What Claude Code is doing ----------
  // claudito-watch works it out for this and the bar widget, and says when
  // something deserves a notification.
  Process {
    id: watcher
    command: ["/usr/bin/python3", "-B", String(Qt.resolvedUrl("claudito-watch")).replace(/^file:\/\//, "")]
    running: true
    stdout: SplitParser { onRead: function(line) { root.notify(line) } }
    stderr: SplitParser { onRead: function(line) { console.warn("claudito-watch:", line.slice(0, 200)) } }
    onExited: restartWatcher.start()
  }
  Timer { id: restartWatcher; interval: 5000; onTriggered: watcher.running = true }

  // Untrusted text: one line and short. The body goes through Plain.plain too.
  function oneLine(value, limit) { return String(value || "").replace(/\s+/g, " ").trim().slice(0, limit) }

  function duration(seconds) {
    seconds = Math.floor(seconds)
    var h = Math.floor(seconds / 3600), m = Math.floor(seconds % 3600 / 60), s = seconds % 60
    if (h > 0) return strings.t("dur.hm").arg(h).arg(m)
    if (m > 0) return strings.t("dur.ms").arg(m).arg(s)
    return strings.t("dur.s").arg(s)
  }

  function notify(line) {
    var n
    try { n = JSON.parse(line) } catch (e) { return }
    if (!n || (n.kind !== "waiting" && n.kind !== "done")) return
    var waiting = n.kind === "waiting"
    if (!(waiting ? settings.notifyWaiting : settings.notifyDone)) return
    var title = strings.t(waiting ? "notify.waiting" : "notify.done")
    var text
    if (waiting) {
      // A permission request says which tool; a question, only that it waits.
      var detail = oneLine(n.detail, 80), tool = oneLine(n.tool, 40)
      text = detail ? (tool ? tool + ": " : "") + detail : strings.t("notify.waitingText")
    } else {
      text = strings.t("notify.doneText").arg(duration(Number(n.seconds) || 0))
    }
    var project = oneLine(n.project, 60)
    if (project) title += " · " + project
    // Out after 5 seconds (the shell keeps higher urgencies up for longer) and,
    // being transient, also out of the history.
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Claudito", "-g", "󰚩",
                             "-u", "low", "-t", "5000", "--transient", title, Plain.plain(text)])
  }

  // Hyprland's window list does not follow fullscreen on its own.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "fullscreen") Hyprland.refreshToplevels()
    }
  }

  function fullscreenOn(screen) {
    var monitor = Hyprland.monitorFor(screen)
    var workspace = monitor ? monitor.activeWorkspace : null
    if (!workspace) return false
    var list = Hyprland.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var ipc = list[i] && list[i].workspace && list[i].workspace.id === workspace.id ? list[i].lastIpcObject : null
      if (ipc && (Number(ipc.fullscreen) & 2) !== 0) return true
    }
    return false
  }

  readonly property real scaleFactor: settings.size === "small" ? 0.7 : settings.size === "large" ? 1.4 : 1
  readonly property int buddyWidth: Math.round(180 * scaleFactor)
  readonly property int buddyHeight: Math.round(150 * scaleFactor)

  ShellIpc {
    target: "corico.claudito"
    function show(): void { settings.set("buddy", true) }
    function hide(): void { settings.set("buddy", false) }
    function toggle(): void { settings.set("buddy", !settings.buddy) }
    function poke(): void {
      var windows = buddies.instances
      for (var i = 0; i < windows.length; i++) windows[i].poke()
    }
    // A screen name (see hyprctl monitors), or "all" for every screen.
    function monitor(name: string): void { settings.set("monitor", name === "all" ? "*" : name) }
  }

  // Every screen for "*", else the chosen one, or the first one if it isn't
  // connected.
  readonly property var targetScreens: {
    var screens = Quickshell.screens
    if (settings.monitor === "*") return screens.slice()
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === settings.monitor) return [screens[i]]
    return screens.length > 0 ? [screens[0]] : []
  }
  readonly property string targetKey: targetScreens.map(function(s) { return s.name }).join(",")

  // A layer-shell surface keeps the layer and screen it was created on, so
  // moving the buddy above or below windows, or to another screen, means
  // building the window again.
  property bool rebuilding: false
  Connections {
    target: settings
    function onOnTopChanged() { root.rebuilding = true; rebuild.restart() }
  }
  onTargetKeyChanged: { rebuilding = true; rebuild.restart() }
  Timer { id: rebuild; interval: 700; onTriggered: root.rebuilding = false }

  Variants {
    id: buddies
    model: settings.loaded && settings.buddy && !root.rebuilding ? root.targetScreens : []

    PanelWindow {
      id: window
      required property var modelData
      screen: modelData
      color: "transparent"

      readonly property bool atTop: settings.corner.indexOf("top") === 0
      readonly property bool atLeft: settings.corner.indexOf("left") > 0

      anchors.top: atTop
      anchors.bottom: !atTop
      anchors.left: atLeft
      anchors.right: !atLeft
      margins.top: Style.space(18)
      margins.bottom: Style.space(18)
      margins.left: Style.space(18)
      margins.right: Style.space(18)

      implicitWidth: root.buddyWidth
      implicitHeight: root.buddyHeight + caption.height + Style.space(6)

      // Normal keeps it clear of the bar's exclusive zone.
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: 0
      WlrLayershell.namespace: "claudito"
      WlrLayershell.layer: settings.onTop ? WlrLayer.Top : WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // A full-screen window covers it: hide, so that it neither draws nor
      // takes clicks meant for that window.
      readonly property bool covered: root.fullscreenOn(modelData)

      mask: covered ? nothing : buddyRegion
      Region { id: buddyRegion; x: buddy.x; y: buddy.y; width: buddy.width; height: buddy.height }
      Region { id: nothing }

      function poke() { pokeAnim.restart() }

      Character {
        id: buddy
        width: root.buddyWidth
        height: root.buddyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: window.atTop ? caption.height + Style.space(6) : 0
        mode: claude.mode
        hat: claude.hat
        seasonHat: settings.wearHat ? root.season : ""
        seasonOutfit: settings.wearOutfit ? root.season : ""
        visible: !window.covered

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: window.poke()
        }

        SequentialAnimation {
          id: pokeAnim
          NumberAnimation { target: buddy; property: "scale"; to: 1.1; duration: Style.duration(120); easing.type: Easing.OutCubic }
          NumberAnimation { target: buddy; property: "scale"; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
        }
      }

      Rectangle {
        id: caption
        visible: !window.covered
        anchors.horizontalCenter: parent.horizontalCenter
        y: window.atTop ? 0 : buddy.height + Style.space(6)
        width: Math.min(parent.width, Math.max(captionText.implicitWidth, projectText.visible ? projectText.implicitWidth : 0) + Style.space(20))
        height: captionCol.implicitHeight + Style.space(8)
        radius: Style.cornerRadius > 0 ? height / 2 : 0
        color: Commons.Util.alpha(Commons.Color.background, 0.8)
        border.width: 1
        border.color: Commons.Util.alpha(Commons.Color.foreground, 0.15)

        Column {
          id: captionCol
          anchors.centerIn: parent
          width: parent.width - Style.space(16)

          Text {
            id: captionText
            width: parent.width
            textFormat: Text.PlainText
            text: claude.label
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
          Text {
            id: projectText
            visible: claude.project !== "" && claude.mode !== "sleep"
            width: parent.width
            textFormat: Text.PlainText
            text: claude.project
            color: Commons.Util.alpha(Commons.Color.foreground, 0.65)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }
}
