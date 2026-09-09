import QtQuick
import QtQuick.Shapes
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
  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

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

  Row {
    id: row
    height: parent.height
    spacing: Style.space(4)

    BarIconButton {
      id: button
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      text: "camera"
      tooltipText: root.recording ? "Recording · click to stop" : root.service.errorMessage !== "" ? "Easy Capture · error, click for details" : "Easy Capture"

      iconComponent: Component {
        Item {
          id: camera
          readonly property color ink: button.foreground

          Item {
            width: 20
            height: 20
            anchors.centerIn: parent
            scale: Math.min(parent.width, parent.height) / 20

            Shape {
              anchors.fill: parent
              antialiasing: true
              ShapePath {
                strokeColor: camera.ink
                strokeWidth: 1.4
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                startX: 3
                startY: 6
                PathLine { x: 6; y: 6 }
                PathLine { x: 7.5; y: 3.5 }
                PathLine { x: 12.5; y: 3.5 }
                PathLine { x: 14; y: 6 }
                PathLine { x: 17; y: 6 }
                PathQuad { x: 18.5; y: 7.5; controlX: 18.5; controlY: 6 }
                PathLine { x: 18.5; y: 15 }
                PathQuad { x: 17; y: 16.5; controlX: 18.5; controlY: 16.5 }
                PathLine { x: 3; y: 16.5 }
                PathQuad { x: 1.5; y: 15; controlX: 1.5; controlY: 16.5 }
                PathLine { x: 1.5; y: 7.5 }
                PathQuad { x: 3; y: 6; controlX: 1.5; controlY: 6 }
              }
            }

            Rectangle {
              x: 6.6
              y: 7.6
              width: 6.8
              height: width
              radius: width / 2
              color: "transparent"
              border.color: camera.ink
              border.width: 1.4
              antialiasing: true
            }

            Rectangle {
              x: 15
              y: 8
              width: 1.5
              height: width
              radius: width / 2
              color: camera.ink
              antialiasing: true
            }
          }
        }
      }

      onPressed: function(mouseButton) {
        if (mouseButton !== Qt.LeftButton) return
        if (root.phase === "recording") root.service.stopRecording()
        else if (root.phase === "idle") root.togglePanel()
      }
    }

    Row {
      visible: root.recording
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
