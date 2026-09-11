import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "." as Backend

// Zipline share settings dialog. The bar panel cannot take exclusive keyboard
// focus, which the token field must, so this lives as an overlay entry point
// summoned by the shell. The server and token are loaded into the shared
// service before opening; saving writes them through the same service.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var captureService: Backend.CaptureService

  property bool opened: false
  property string errorText: ""
  property string fontFamily: Style.font.menuFamily
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property color dim: Qt.darker(foreground, 1.45)

  readonly property int cardWidth: Math.min(Style.space(420), panel.width - Style.gapsOut * 2)
  readonly property bool hasServer: serverField.text !== ""
  readonly property bool hasToken: tokenField.text !== ""

  onOpenedChanged: if (opened) {
    serverField.text = captureService.shareServer
    tokenField.text = captureService.shareToken
    errorText = ""
  }
  Connections {
    target: root.captureService
    function onShareServerChanged() { if (root.opened && !serverField.activeFocus) serverField.text = root.captureService.shareServer }
    function onShareTokenChanged() { if (root.opened && !tokenField.activeFocus) tokenField.text = root.captureService.shareToken }
  }

  function open(payloadJson) {
    root.errorText = ""
    root.opened = true
    if (root.captureService) root.captureService.loadConfig()
    Qt.callLater(function() { serverField.forceActiveFocus() })
  }

  function close() { root.opened = false; if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "chyld.easy-capture") }

  function save() {
    var server = serverField.text.trim()
    var token = tokenField.text.trim()
    if (server === "" || token === "") { errorText = "Both a server URL and a token are required."; return }
    if (!/^https:\/\//.test(server)) { errorText = "Zipline share server must use https://"; return }
    captureService.saveConfig(server, token)
    root.close()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-easy-capture-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + Style.spacing.panelPadding * 2
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec

      MouseArea { anchors.fill: parent; onClicked: {} }

      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.close()

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        spacing: Style.space(12)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "Zipline share settings"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.errorText !== ""
            ? root.errorText
            : "When 'Share' is on, screenshots are uploaded and the link is copied to the clipboard."
          color: root.errorText !== "" ? Color.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: "Server URL"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: serverField
            width: parent.width
            foreground: root.foreground
            onAccepted: tokenField.forceActiveFocus()
            KeyNavigation.tab: tokenField
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: "Auth token"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            id: tokenField
            width: parent.width
            password: true
            foreground: root.foreground
            onAccepted: root.save()
            KeyNavigation.tab: serverField
          }
        }

        Row {
          anchors.right: parent.right
          spacing: Style.space(8)

          Button {
            text: "Cancel"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.close()
          }

          Button {
            text: "Save"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            active: root.hasServer && root.hasToken
            enabled: root.hasServer && root.hasToken
            onClicked: root.save()
          }
        }
      }
    }
  }
}
