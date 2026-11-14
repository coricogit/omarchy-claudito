import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

import "ui"

// Claudito on the desktop: a small layer-shell window in a corner of the
// first screen. It sits under your windows like a desktop widget, or above
// them if you turn that on in the bar panel. Only the buddy itself takes
// clicks (to poke it); the rest of the window lets them through.
Scope {
  id: root

  property var shell: null
  property var manifest: null

  ClauditoState { id: claude }
  BuddySettings { id: settings }

  readonly property real scaleFactor: settings.size === "small" ? 0.7 : settings.size === "large" ? 1.4 : 1
  readonly property int buddyWidth: Math.round(180 * scaleFactor)
  readonly property int buddyHeight: Math.round(150 * scaleFactor)

  ShellIpc {
    target: "corico.claudito"
    function show(): void { settings.set("buddy", true) }
    function hide(): void { settings.set("buddy", false) }
    function toggle(): void { settings.set("buddy", !settings.buddy) }
    function poke(): void { if (buddyLoader.item) buddyLoader.item.poke() }
  }

  // A layer-shell surface keeps the layer it was created on, so moving the
  // buddy above or below windows means building the window again.
  property bool rebuilding: false
  Connections {
    target: settings
    function onOnTopChanged() { root.rebuilding = true; rebuild.restart() }
  }
  Timer { id: rebuild; interval: 700; onTriggered: root.rebuilding = false }

  LazyLoader {
    id: buddyLoader
    active: settings.loaded && settings.buddy && !root.rebuilding && Quickshell.screens.length > 0

    PanelWindow {
      id: window
      screen: Quickshell.screens[0]
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

      mask: Region { x: buddy.x; y: buddy.y; width: buddy.width; height: buddy.height }

      function poke() { pokeAnim.restart() }

      Character {
        id: buddy
        width: root.buddyWidth
        height: root.buddyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: window.atTop ? caption.height + Style.space(6) : 0
        mode: claude.mode
        hat: claude.hat

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
