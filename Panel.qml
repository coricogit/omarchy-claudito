import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons

import "ui"

// Claude usage in the Omarchy bar: a tiny Claudito plus how much of the
// 5-hour window you've used. The panel shows the plan limits, the current
// Claude Code session, token history, the account, and the desktop buddy's
// settings. Data comes from claudito-usage, next to this file; claudito-hook
// and claudito-statusline feed it once ./setup has connected Claude Code.
Panel {
  id: root
  moduleName: "corico.claudito"
  ipcTarget: "corico.claudito.panel"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  ClauditoState { id: claude }
  BuddySettings { id: buddySettings }

  readonly property string backend: String(Qt.resolvedUrl("claudito-usage")).replace(/^file:\/\//, "")
  readonly property string setupScript: String(Qt.resolvedUrl("setup")).replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color coral: "#EE7E55"

  property var usage: null
  property bool connected: true
  property string connectError: ""
  property string backendError: ""
  property real now: Date.now() / 1000
  property bool showEmail: false
  property int period: 0   // 0 today, 1 week, 2 month

  readonly property var account: usage && usage.account ? usage.account : ({})
  readonly property var live: usage ? usage.live : null
  readonly property var limits: live && live.limits ? live.limits : ({})
  readonly property var five: limits.five_hour || null
  readonly property var week: limits.seven_day || null
  readonly property real fivePct: five && typeof five.percent === "number" ? five.percent : -1
  readonly property real weekPct: week && typeof week.percent === "number" ? week.percent : -1
  readonly property bool liveActive: !!(live && live.updated && now - live.updated < 120)
  readonly property var periodData: usage && usage.periods ? usage.periods[["today", "week", "month"][period]] : null

  readonly property string mood: {
    if (claude.mode === "waiting" || claude.mode === "oops") return "worried"
    if (fivePct >= 80) return "worried"
    if (claude.busy) return "focus"
    if (fivePct < 0 && claude.mode === "sleep") return "sleep"
    return fivePct >= 50 ? "focus" : "happy"
  }

  // ---------- Formatting ----------
  function pctText(v) { return v < 0 ? "?" : Commons.I18n.formatNumber(Math.round(v)) + "%" }

  function fmtTokens(n) {
    n = n || 0
    if (n >= 1e9) return Commons.I18n.formatNumber(n / 1e9, 1) + " B"
    if (n >= 1e6) return Commons.I18n.formatNumber(n / 1e6, 1) + " M"
    if (n >= 1e3) return Commons.I18n.formatNumber(n / 1e3, 1) + " k"
    return Commons.I18n.formatNumber(n)
  }

  function fmtDuration(sec) {
    sec = Math.max(0, Math.round(sec))
    var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
    if (d > 0) return strings.t("dur.dh").arg(d).arg(h)
    if (h > 0) return strings.t("dur.hm").arg(h).arg(m)
    if (m > 0) return strings.t("dur.m").arg(m)
    return strings.t("dur.s").arg(sec)
  }

  function resetText(lim) {
    if (!lim || !lim.resetsAt) return lim && lim.percent === 0 ? strings.t("reset") : ""
    var left = lim.resetsAt - now
    if (left <= 0) return strings.t("reset")
    if (left < 86400) return strings.t("resetsIn").arg(fmtDuration(left))
    var d = new Date(lim.resetsAt * 1000)
    return strings.t("resetsAt").arg(d.toLocaleString(Qt.locale(Commons.I18n.formatLocale), "ddd d, HH:mm"))
  }

  function maskEmail(e) {
    e = String(e || "")
    if (!e) return ""
    var at = e.indexOf("@")
    if (at < 0) return "•••"
    return e.slice(0, Math.min(2, at)) + "•••" + e.slice(at)
  }

  function levelColor(v) {
    return v >= 80 ? Commons.Color.urgent : fg
  }

  function planName() {
    var p = String(account.subscriptionType || account.planTier || "").slice(0, 30)
    return p ? strings.t("plan").arg(p.charAt(0).toUpperCase() + p.slice(1)) : "Claudito"
  }

  // ---------- Data ----------
  function refresh() {
    if (!usageProc.running) usageProc.running = true
    if (!checkProc.running) checkProc.running = true
  }

  function connectClaude() {
    connectError = ""
    if (!connectProc.running) connectProc.running = true
  }

  // Is Claude Code hooked up? ./setup --check exits 0 when it is.
  Process {
    id: checkProc
    command: ["/bin/bash", root.setupScript, "--check"]
    onExited: function(code) { root.connected = code === 0 }
  }

  Process {
    id: connectProc
    command: ["/bin/bash", root.setupScript]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.connectError = String(text || "").trim().slice(0, 160)
    }
    onExited: function(code) { root.refresh() }
  }

  Process {
    id: usageProc
    command: ["/usr/bin/python3", root.backend]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          if (parsed && typeof parsed === "object") { root.usage = parsed; root.backendError = "" }
        } catch (e) {
          root.backendError = "bad"
        }
      }
    }
    onExited: function(code) { if (code !== 0) root.backendError = code === 2 ? "missing" : "failed" }
  }

  Timer {
    interval: root.opened ? 5000 : 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: { root.now = Date.now() / 1000; root.refresh() }
  }
  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.now = Date.now() / 1000
  }

  // Keyboard cursor over the controls: j/k walk rows, h/l walk the choices.
  property string focusSection: "period"
  property int selectedIndex: 0
  property bool cursorActive: false
  readonly property var sections: connected
    ? ["period", "buddy", "onTop", "monitor", "corner", "size", "web"]
    : ["connect", "period", "buddy", "onTop", "monitor", "corner", "size", "web"]

  function moveCursor(dy) {
    var i = Math.max(0, sections.indexOf(focusSection))
    focusSection = sections[Math.max(0, Math.min(sections.length - 1, i + dy))]
    if (focusSection === "period") selectedIndex = period
    else if (focusSection === "corner") selectedIndex = buddySettings.corners.indexOf(buddySettings.corner)
    else if (focusSection === "monitor") selectedIndex = Math.max(0, monitorIndex())
    else if (focusSection === "size") selectedIndex = buddySettings.sizes.indexOf(buddySettings.size)
    else selectedIndex = -1
  }

  function moveCursorH(dx) {
    var count = focusSection === "period" ? 3 : focusSection === "corner" ? 4 : focusSection === "size" ? 3
      : focusSection === "monitor" ? Quickshell.screens.length : 0
    if (count > 0) selectedIndex = (Math.max(0, selectedIndex) + dx + count) % count
  }

  function activateCursor() {
    if (focusSection === "period") period = selectedIndex
    else if (focusSection === "buddy") buddySettings.set("buddy", !buddySettings.buddy)
    else if (focusSection === "onTop") buddySettings.set("onTop", !buddySettings.onTop)
    else if (focusSection === "corner") buddySettings.set("corner", buddySettings.corners[selectedIndex])
    else if (focusSection === "size") buddySettings.set("size", buddySettings.sizes[selectedIndex])
    else if (focusSection === "monitor" && Quickshell.screens[selectedIndex]) buddySettings.set("monitor", Quickshell.screens[selectedIndex].name)
    else if (focusSection === "web") openUsage()
    else if (focusSection === "connect") connectClaude()
  }

  // Which screen the buddy is on: the chosen one, or the first if it's gone.
  function monitorIndex() {
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === buddySettings.monitor) return i
    return 0
  }

  function hoverCursor(section, index) {
    focusSection = section
    selectedIndex = index
  }

  function openUsage() {
    Qt.openUrlExternally("https://claude.ai/settings/usage")
    root.close()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      showEmail = false
      now = Date.now() / 1000
      refresh()
    }
  }

  // ---------- Bar button ----------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : barRow.implicitWidth + Style.space(12)
    fixedHeight: vertical ? barRow.implicitHeight + Style.space(10) : -1
    tooltipText: strings.t("tooltip").arg(root.pctText(root.fivePct)).arg(root.pctText(root.weekPct))
      + "\n" + claude.label
    onPressed: function(b) { root.toggle() }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      scale: button.pressScale

      Item {
        width: 16
        height: 14
        anchors.verticalCenter: parent.verticalCenter

        MiniClaudito {
          id: mini
          width: 16
          height: 14
          mood: root.mood
          // A one-pixel hop while Claude Code is working.
          y: claude.busy && hop.on && Style.duration(100) > 0 ? -1 : 0
        }
        Timer {
          id: hop
          property bool on: false
          interval: 260
          repeat: true
          running: claude.busy
          onTriggered: on = !on
          onRunningChanged: if (!running) on = false
        }
      }

      Text {
        visible: root.fivePct >= 0 && !(root.bar && root.bar.vertical)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.pctText(root.fivePct)
        color: root.fivePct >= 80 ? Commons.Color.urgent : root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: root.fivePct >= 80
        renderType: Text.NativeRendering
      }
    }
  }

  // ---------- Panel ----------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(820))

    content: PanelKeyCatcher {
      implicitHeight: panelColumn.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; root.moveCursor(0); return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: the live buddy and the account ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroBuddy.height, heroLabels.implicitHeight)

            Character {
              id: heroBuddy
              width: Style.space(84)
              height: Style.space(70)
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              mode: claude.mode
              hat: claude.hat
            }

            Column {
              id: heroLabels
              anchors.left: heroBuddy.right
              anchors.leftMargin: Style.space(10)
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              PlainLabel {
                text: root.planName()
                font.pixelSize: Style.font.title
                font.bold: true
                width: parent.width
              }
              PlainLabel {
                text: claude.label
                font.pixelSize: Style.font.bodySmall
                width: parent.width
              }
              PlainLabel {
                visible: claude.project !== "" && claude.mode !== "sleep"
                text: claude.project
                color: root.dim
                font.pixelSize: Style.font.caption
                width: parent.width
              }
              PlainLabel {
                visible: !!root.account.email
                text: root.showEmail ? String(root.account.email || "") : root.maskEmail(root.account.email)
                color: root.dim
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                width: parent.width

                MouseArea {
                  id: emailMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showEmail = !root.showEmail
                  PanelToolTip {
                    visible: emailMouse.containsMouse
                    text: root.showEmail ? strings.t("hideEmail") : strings.t("showEmail")
                    fontFamily: root.fontFamily
                  }
                }
              }
              PlainLabel {
                visible: !!root.account.loginExpiresAt
                text: root.account.loginExpiresAt
                  ? strings.t("loginUntil").arg(new Date(root.account.loginExpiresAt).toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "d MMM yyyy"))
                  : ""
                color: root.dim
                font.pixelSize: Style.font.caption
                width: parent.width
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.top: parent.top
              iconText: "󰑐"
              tooltipText: strings.t("refresh")
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }
          }

          // ---------- Not connected to Claude Code yet ----------
          Column {
            visible: !root.connected
            width: parent.width
            spacing: Style.space(8)

            PlainLabel {
              text: strings.t("connect.text")
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              elide: Text.ElideNone
              width: parent.width
            }
            Button {
              text: strings.t("connect.button")
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              hasCursor: root.cursorActive && root.focusSection === "connect"
              onClicked: root.connectClaude()
              onHovered: function(isHovered) { if (isHovered) root.hoverCursor("connect", -1) }
            }
            PlainLabel {
              visible: root.connectError !== ""
              text: root.connectError
              color: Commons.Color.urgent
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              elide: Text.ElideNone
              width: parent.width
            }
          }

          PlainLabel {
            visible: root.backendError !== ""
            text: root.backendError === "missing" ? strings.t("error.missing") : strings.t("error.failed")
            color: Commons.Color.urgent
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            elide: Text.ElideNone
            width: parent.width
          }

          // ---------- Plan limits ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: strings.t("limits"); foreground: root.fg; fontFamily: root.fontFamily }

            PlainLabel {
              visible: !root.five && !root.week
              text: strings.t("noLimits")
              color: root.dim
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              elide: Text.ElideNone
              width: parent.width
            }

            LimitRow { visible: !!root.five; label: strings.t("fiveHour"); value: root.fivePct; lim: root.five }
            LimitRow { visible: !!root.week; label: strings.t("week"); value: root.weekPct; lim: root.week }

            PlainLabel {
              visible: (!!root.five || !!root.week) && !!root.live && !root.liveActive
              text: strings.t("staleLimits").arg(root.live && root.live.updated ? root.fmtDuration(root.now - root.live.updated) : "")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
          }

          // ---------- Current session ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: strings.t("session"); foreground: root.fg; fontFamily: root.fontFamily }

            PlainLabel {
              visible: !root.live
              text: strings.t("noSession")
              color: root.dim
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              elide: Text.ElideNone
              width: parent.width
            }

            Column {
              visible: !!root.live
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)
                Rectangle {
                  width: Style.space(7); height: width; radius: width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.liveActive ? root.coral : Commons.Util.alpha(root.fg, 0.3)
                }
                PlainLabel {
                  text: root.live ? String(root.live.sessionName || root.live.project || "").slice(0, 80) : ""
                  font.pixelSize: Style.font.body
                  font.bold: true
                  width: parent.width - Style.space(13)
                }
              }
              PlainLabel {
                text: root.live ? [root.live.model, root.live.project, root.live.version ? "v" + root.live.version : ""]
                  .filter(function(x) { return x }).map(function(x) { return String(x).slice(0, 40) }).join(" · ") : ""
                color: root.dim
                font.pixelSize: Style.font.caption
                width: parent.width
              }

              KV {
                key: strings.t("context")
                value: root.live && typeof root.live.contextPercent === "number"
                  ? strings.t("contextOf").arg(Commons.I18n.formatNumber(Math.round(root.live.contextPercent))).arg(root.fmtTokens(root.live.contextSize)) : "?"
              }
              Meter { value: root.live && typeof root.live.contextPercent === "number" ? root.live.contextPercent : 0 }
              KV {
                key: strings.t("duration")
                value: root.live && root.live.durationMs
                  ? strings.t("durationValue").arg(root.fmtDuration(root.live.durationMs / 1000)).arg(root.fmtDuration((root.live.apiDurationMs || 0) / 1000)) : "?"
              }
              KV {
                key: strings.t("lines")
                value: root.live ? "+" + Commons.I18n.formatNumber(root.live.linesAdded || 0) + " / −" + Commons.I18n.formatNumber(root.live.linesRemoved || 0) : ""
              }
              KV {
                key: strings.t("cost")
                value: root.live && typeof root.live.costUsd === "number" ? "$" + Commons.I18n.formatNumber(root.live.costUsd, 2) : "?"
                hint: strings.t("costHint")
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader { text: strings.t("usage"); foreground: root.fg; fontFamily: root.fontFamily }

            Grid {
              id: periodRow
              width: parent.width
              columns: 3
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
              Repeater {
                model: [strings.t("today"), strings.t("days7"), strings.t("days30")]
                OptionPill {
                  required property string modelData
                  required property int index
                  section: "period"
                  optionIndex: index
                  width: periodRow.cellWidth
                  text: modelData
                  active: root.period === index
                  onClicked: root.period = index
                }
              }
            }

            Grid {
              id: statGrid
              width: parent.width
              columns: 3
              rowSpacing: Style.space(8)
              columnSpacing: Style.space(8)
              readonly property real cellWidth: (width - columnSpacing * (columns - 1)) / columns
              Stat { label: strings.t("output"); value: root.periodData ? root.fmtTokens(root.periodData.out) : "–" }
              Stat { label: strings.t("input"); value: root.periodData ? root.fmtTokens(root.periodData.in + root.periodData.cacheW) : "–" }
              Stat { label: strings.t("cacheRead"); value: root.periodData ? root.fmtTokens(root.periodData.cacheR) : "–" }
              Stat { label: strings.t("messages"); value: root.periodData ? Commons.I18n.formatNumber(root.periodData.msgs) : "–" }
              Stat { label: strings.t("sessions"); value: root.periodData ? Commons.I18n.formatNumber(root.periodData.sessions || 0) : "–" }
            }

            PlainLabel {
              text: strings.t("perDay")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }

            Item {
              id: chart
              readonly property var days: root.usage && Array.isArray(root.usage.daily) ? root.usage.daily.slice(-14) : []
              readonly property real maxOut: Math.max.apply(null, [1].concat(days.map(function(d) { return d.out || 0 })))
              width: parent.width
              height: Style.space(56)

              Row {
                anchors.fill: parent
                spacing: Style.space(2)
                Repeater {
                  model: chart.days
                  Item {
                    required property var modelData
                    required property int index
                    width: (chart.width - Style.space(2) * (chart.days.length - 1)) / Math.max(1, chart.days.length)
                    height: chart.height

                    Rectangle {
                      anchors.bottom: parent.bottom
                      width: parent.width
                      height: Math.max(2, parent.height * (modelData.out || 0) / chart.maxOut)
                      radius: Math.min(2, Style.cornerRadius)
                      color: index === chart.days.length - 1 ? root.coral : Commons.Util.alpha(root.coral, 0.5)
                      opacity: modelData.out > 0 ? 1 : 0.3
                    }
                    MouseArea { id: barMouse; anchors.fill: parent; hoverEnabled: true }
                    PanelToolTip {
                      visible: barMouse.containsMouse
                      fontFamily: root.fontFamily
                      text: new Date(String(modelData.day) + "T12:00:00").toLocaleDateString(Qt.locale(Commons.I18n.formatLocale), "ddd d MMM")
                        + "\n" + strings.t("output") + ": " + root.fmtTokens(modelData.out)
                        + "\n" + strings.t("messages") + ": " + Commons.I18n.formatNumber(modelData.msgs || 0)
                    }
                  }
                }
              }
            }

            PlainLabel {
              text: strings.t("projects")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
            ShareList { rows: root.usage && Array.isArray(root.usage.projects) ? root.usage.projects : [] }

            PlainLabel {
              text: strings.t("models")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
            ShareList { rows: root.usage && Array.isArray(root.usage.models) ? root.usage.models : [] }
          }

          // ---------- Desktop buddy ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader { text: strings.t("buddy"); foreground: root.fg; fontFamily: root.fontFamily }

            Toggle {
              width: parent.width
              label: strings.t("buddy.show")
              description: strings.t("buddy.showHint")
              checked: buddySettings.buddy
              hasCursor: root.cursorActive && root.focusSection === "buddy"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: buddySettings.set("buddy", !buddySettings.buddy)
              onHovered: function(isHovered) { if (isHovered) root.hoverCursor("buddy", -1) }
            }

            Toggle {
              width: parent.width
              enabled: buddySettings.buddy
              opacity: enabled ? 1 : 0.5
              label: strings.t("buddy.onTop")
              description: strings.t("buddy.onTopHint")
              checked: buddySettings.onTop
              hasCursor: root.cursorActive && root.focusSection === "onTop"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: buddySettings.set("onTop", !buddySettings.onTop)
              onHovered: function(isHovered) { if (isHovered) root.hoverCursor("onTop", -1) }
            }

            PlainLabel {
              visible: Quickshell.screens.length > 1
              text: strings.t("buddy.monitor")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
            Grid {
              id: monitorRow
              visible: Quickshell.screens.length > 1
              width: parent.width
              columns: Math.max(1, Math.min(4, Quickshell.screens.length))
              spacing: Style.spacing.xs
              enabled: buddySettings.buddy
              opacity: enabled ? 1 : 0.5
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
              Repeater {
                model: Quickshell.screens
                OptionPill {
                  required property var modelData
                  required property int index
                  section: "monitor"
                  optionIndex: index
                  width: monitorRow.cellWidth
                  text: String(modelData.name || "?").slice(0, 20)
                  active: root.monitorIndex() === index
                  onClicked: buddySettings.set("monitor", modelData.name)
                }
              }
            }

            PlainLabel {
              text: strings.t("buddy.corner")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
            Grid {
              id: cornerRow
              width: parent.width
              columns: 4
              spacing: Style.spacing.xs
              enabled: buddySettings.buddy
              opacity: enabled ? 1 : 0.5
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
              Repeater {
                model: buddySettings.corners
                OptionPill {
                  required property string modelData
                  required property int index
                  section: "corner"
                  optionIndex: index
                  width: cornerRow.cellWidth
                  text: strings.t("corner." + modelData)
                  active: buddySettings.corner === modelData
                  onClicked: buddySettings.set("corner", modelData)
                }
              }
            }

            PlainLabel {
              text: strings.t("buddy.size")
              color: root.dim
              font.pixelSize: Style.font.caption
              width: parent.width
            }
            Grid {
              id: sizeRow
              width: parent.width
              columns: 3
              spacing: Style.spacing.xs
              enabled: buddySettings.buddy
              opacity: enabled ? 1 : 0.5
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
              Repeater {
                model: buddySettings.sizes
                OptionPill {
                  required property string modelData
                  required property int index
                  section: "size"
                  optionIndex: index
                  width: sizeRow.cellWidth
                  text: strings.t("size." + modelData)
                  active: buddySettings.size === modelData
                  onClicked: buddySettings.set("size", modelData)
                }
              }
            }
          }

          Button {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰖟  " + strings.t("openUsage")
            fontSize: Style.font.caption
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            hasCursor: root.cursorActive && root.focusSection === "web"
            onClicked: root.openUsage()
            onHovered: function(isHovered) { if (isHovered) root.hoverCursor("web", -1) }
          }

          Item { width: parent.width; height: Style.space(2) }
        }
      }
    }
  }

  // ---------- Building blocks ----------
  component PlainLabel: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    elide: Text.ElideRight
  }

  component Meter: Rectangle {
    property real value: 0
    width: parent ? parent.width : 0
    height: Style.space(4)
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: Commons.Util.alpha(root.fg, 0.12)
    Rectangle {
      width: parent.width * Math.max(0, Math.min(100, parent.value)) / 100
      height: parent.height
      radius: parent.radius
      color: parent.value >= 80 ? Commons.Color.urgent : root.coral
    }
  }

  component LimitRow: Column {
    id: limitRow
    property string label
    property real value: -1
    property var lim
    width: parent ? parent.width : 0
    spacing: Style.space(4)

    Item {
      width: parent.width
      implicitHeight: limitName.implicitHeight
      PlainLabel { id: limitName; text: limitRow.label; font.pixelSize: Style.font.body; anchors.left: parent.left }
      PlainLabel {
        text: root.pctText(limitRow.value)
        font.pixelSize: Style.font.body
        font.bold: true
        color: root.levelColor(limitRow.value)
        anchors.right: parent.right
      }
    }
    Meter { value: Math.max(0, limitRow.value) }
    PlainLabel {
      text: root.resetText(limitRow.lim)
      color: root.dim
      font.pixelSize: Style.font.caption
      width: parent.width
    }
  }

  component KV: Item {
    id: kv
    property string key
    property string value
    property string hint: ""
    width: parent ? parent.width : 0
    implicitHeight: kvKey.implicitHeight
    PlainLabel { id: kvKey; text: kv.key; color: root.dim; font.pixelSize: Style.font.bodySmall; anchors.left: parent.left }
    PlainLabel {
      id: kvValue
      text: kv.value
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      MouseArea { id: kvMouse; anchors.fill: parent; hoverEnabled: kv.hint !== "" }
      PanelToolTip { visible: kvMouse.containsMouse && kv.hint !== ""; text: kv.hint; fontFamily: root.fontFamily }
    }
  }

  component Stat: Column {
    id: stat
    property string label
    property string value
    width: statGrid.cellWidth
    spacing: 0
    PlainLabel { text: stat.value; font.pixelSize: Style.font.subtitle; font.bold: true; width: parent.width }
    PlainLabel { text: stat.label; color: root.dim; font.pixelSize: Style.font.caption; width: parent.width }
  }

  component ShareList: Column {
    id: share
    property var rows: []
    readonly property real total: (rows || []).reduce(function(a, r) { return a + (r.out || 0) }, 0) || 1
    width: parent ? parent.width : 0
    spacing: Style.space(6)

    PlainLabel {
      visible: !share.rows || share.rows.length === 0
      text: strings.t("noData")
      color: root.dim
      font.pixelSize: Style.font.caption
    }
    Repeater {
      model: share.rows
      Column {
        required property var modelData
        width: share.width
        spacing: Style.space(2)
        Item {
          width: parent.width
          implicitHeight: shareName.implicitHeight
          PlainLabel {
            id: shareName
            text: String(modelData.name || "?").replace(/^claude-/, "").slice(0, 60)
            font.pixelSize: Style.font.bodySmall
            anchors.left: parent.left
            anchors.right: shareValue.left
            anchors.rightMargin: Style.space(8)
          }
          PlainLabel {
            id: shareValue
            text: root.fmtTokens(modelData.out)
            color: root.dim
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
        Meter { value: 100 * (modelData.out || 0) / share.total }
      }
    }
  }

  component OptionPill: Button {
    id: pill
    required property string section
    required property int optionIndex
    fontSize: Style.font.caption
    foreground: root.fg
    fontFamily: root.fontFamily
    horizontalPadding: Style.spacing.xs
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true
    hasCursor: root.cursorActive && root.focusSection === section && root.selectedIndex === optionIndex
    onHovered: function(isHovered) { if (isHovered) root.hoverCursor(pill.section, pill.optionIndex) }
  }
}
