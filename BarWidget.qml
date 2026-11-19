import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "." as Backend

// Each monitor gets a view. All capture state and process ownership are shared.
BarWidget {
  id: root
  moduleName: "chyld.easy-capture"
  readonly property var service: Backend.CaptureService
  readonly property string phase: service.phase
  readonly property bool recording: service.recording
  readonly property string elapsedTimeText: service.elapsedTimeText
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  property string subscription: ""
  // Same shape as the built-in bar widgets: the icon button fills the widget's
  // height, and only the recording timer sits beside it.
  implicitWidth: button.implicitWidth + (recordingRow.visible ? recordingRow.implicitWidth + Style.space(4) : 0)
  implicitHeight: button.implicitHeight

  Component.onCompleted: subscription = service.acquire()
  Component.onDestruction: service.release(subscription)
  onOpenedChanged: service.setPanelVisible(subscription, opened)
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = button
    panel.hostWidget = root
    panel.service = root.service
  }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (opened) close(); else open() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  Connections {
    target: root.service
    function onCaptureRequested() { root.close() }
  }
  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("CapturePanel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Item {
    id: row
    anchors.fill: parent

    BarIconButton {
      id: button
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      bar: root.bar
      text: "󰄀"   // nf-md-camera: a font glyph is sized and centred by the bar like its other icons
      tooltipText: root.recording ? "Recording · click to stop" : root.service.errorMessage !== "" ? "Easy Capture · error, click for details" : "Easy Capture"

      onPressed: function(mouseButton) {
        if (mouseButton !== Qt.LeftButton) return
        if (root.phase === "recording") root.service.stopRecording()
        else if (root.phase === "idle") root.togglePanel()
      }
    }

    Row {
      id: recordingRow
      visible: root.recording
      anchors.left: button.right
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Rectangle {
        width: Style.space(8)
        height: width
        radius: width / 2
        color: root.bar ? root.bar.urgent : Color.urgent
        anchors.verticalCenter: parent.verticalCenter

        SequentialAnimation on opacity {
          running: root.phase === "recording"
          loops: Animation.Infinite
          NumberAnimation { from: 1.0; to: 0.3; duration: 700 }
          NumberAnimation { from: 0.3; to: 1.0; duration: 700 }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: root.elapsedTimeText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

}
