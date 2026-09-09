import QtQuick
import Quickshell
import "plugin" as Plugin

Scope {
  id: test
  property var widgetA: null
  property var widgetB: null
  property int stage: 0
  property int ticks: 0
  readonly property var service: Plugin.CaptureService
  QtObject {
    id: host
    property string captureMode: "screenshot"
    property string targetType: "region"
    property bool desktopAudio: false
    property bool microphoneAudio: false
    property var microphoneInputs: [{name:"onboard",label:"Onboard"},{name:"usb",label:"USB headset"}]
    property string selectedMicrophone: ""
    property string microphoneMessage: ""
    property string errorMessage: ""
    property string selectedMonitor: ""
    property var monitors: [{name:"DP-1"},{name:"DP-2"}]
    property string phase: "idle"
    property string captured: ""
    readonly property bool canStart: targetType !== "monitor" || selectedMonitor !== ""
    function setSelectedMicrophone(value) { selectedMicrophone = value }
    function setTargetType(value) { targetType = value }
    function setSelectedMonitor(value) { selectedMonitor = value }
    function startCapture(value) { captured = value }
  }
  Plugin.CapturePanel { id: panel; service: host }
  function check(value, message) { if (!value) throw new Error("FAIL " + message) }
  function uiTests() {
    check(panel.captureMode === "screenshot" && !host.desktopAudio && !host.microphoneAudio, "initial state")
    panel.setCursor("mode", 1); panel.activateCursor()
    check(host.captureMode === "record" && host.captured === "", "tab is not capture")
    panel.setCursor("audio", 0); panel.activateCursor()
    check(host.desktopAudio && !host.microphoneAudio, "independent desktop toggle")
    panel.moveCursor(1); panel.activateCursor()
    check(host.microphoneAudio && panel.showMicrophonePicker, "microphone and picker")
    panel.setCursor("microphone", 2); panel.activateCursor()
    check(host.selectedMicrophone === "usb", "select microphone")
    host.microphoneInputs = [{name:"usb",label:"USB"}]
    check(!panel.showMicrophonePicker, "hide single input picker")
    host.microphoneInputs = []
    check(!panel.showMicrophonePicker, "hide empty picker")
    panel.setCursor("target", 2); panel.activateCursor()
    check(!panel.canStart, "monitor gating")
    panel.setCursor("capture", 0); panel.activateCursor()
    check(host.captured === "", "cannot capture without monitor")
    panel.setCursor("monitor", 1); panel.activateCursor()
    panel.setCursor("capture", 0); panel.activateCursor()
    check(host.captured === "record", "record trigger")
    panel.setCursor("mode", 0); panel.activateCursor()
    check(panel.visibleSections.indexOf("audio") < 0, "audio hidden on screenshots")
    panel.setCursor("capture", 0); panel.activateCursor()
    check(host.captured === "screenshot", "screenshot trigger")
    panel.tabCursor(1); check(panel.focusSection === "mode", "tab wraps")
    panel.tabCursor(-1); check(panel.focusSection === "capture", "shift tab wraps")
  }
  Timer {
    interval: 50
    running: true
    repeat: true
    onTriggered: {
      try {
        check(++test.ticks < 200, "test deadline")
        if (test.stage === 0) {
          uiTests()
          var component = Qt.createComponent("plugin/BarWidget.qml")
          check(component.status === Component.Ready, component.errorString())
          widgetA = component.createObject(test)
          widgetB = component.createObject(test)
          check(widgetA && widgetB && widgetA.service === widgetB.service, "widgets share service")
          check(Object.keys(service.consumers).length === 2, "two subscriptions")
          check(!service.panelVisible && service.monitors.length === 0, "load does not start discovery")
          check(!service.startCapture("record"), "no capture without open panel")
          service.setPanelVisible(widgetA.subscription, true)
          test.stage = 1
        } else if (test.stage === 1 && service.monitors.length === 2 && service.microphoneInputs.length === 2) {
          service.captureMode = "record"
          service.microphoneAudio = true
          service.setSelectedMicrophone("usb")
          check(service.startCapture("record"), "start capture")
          check(!service.startCapture("record"), "single flight")
          check(service.pendingRequest.input === "usb", "immutable selected input")
          test.stage = 2
        } else if (test.stage === 2 && service.recording) {
          check(widgetA.recording && widgetB.recording, "recording on both monitors")
          service.stopRecording()
          test.stage = 3
        } else if (test.stage === 3 && service.phase === "idle" && service.lastSaved !== "") {
          check(service.errorMessage === "", "successful result")
          service.setPanelVisible(widgetA.subscription, true)
          check(service.startCapture("record"), "second capture")
          test.stage = 4
        } else if (test.stage === 4 && service.recording) {
          widgetA.destroy(); widgetA = null
          test.stage = 5
        } else if (test.stage === 5) {
          check(service.recording && Object.keys(service.consumers).length === 1, "one removal keeps recording")
          widgetB.destroy(); widgetB = null
          test.stage = 6
        } else if (test.stage === 6) {
          check(!service.active && service.phase === "idle", "last removal cancels capture")
          test.stage = 7
        } else if (test.stage === 7) {
          console.log("PASS interface, shared state, immutable request, single flight and removal cleanup")
          finish.start(); running = false
        }
      } catch (error) {
        console.error(String(error)); finish.start(); running = false
      }
    }
  }
  Timer { id: finish; interval: 250; onTriggered: Qt.quit() }
}
