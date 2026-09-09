import QtQuick
import Quickshell
import "plugin" as Plugin

Scope {
  id: test
  QtObject {
    id: host
    property string captureMode: "screenshot"
    property string targetType: "region"
    property bool desktopAudio: false
    property bool microphoneAudio: false
    property var microphoneInputs: [{name: "onboard", label: "Onboard"}, {name: "usb", label: "USB headset"}]
    property string selectedMicrophone: ""
    property string microphoneMessage: ""
    function setSelectedMicrophone(value) { selectedMicrophone = value }
    property string selectedMonitor: ""
    property var monitors: [{name: "DP-1"}, {name: "DP-2"}]
    property string phase: "idle"
    property string captured: ""
    readonly property bool canStart: targetType !== "monitor" || selectedMonitor !== ""
    function setTargetType(value) { targetType = value }
    function setSelectedMonitor(value) { selectedMonitor = value }
    function startCapture(value) { captured = value }
  }
  Plugin.CapturePanel { id: panel; hostWidget: host }
  Plugin.BarWidget { id: widget }
  function check(value, message) {
    if (!value) throw new Error("FAIL " + message)
  }
  Timer {
    interval: 250
    running: true
    onTriggered: {
      try {
        var appCommand = widget.pickerCommand("windows")
        check(appCommand[1].endsWith("/capture-region.sh") && appCommand[2] === "windows", "app uses all-monitor helper")
        check(widget.pickerCommand("region").indexOf("omarchy-capture-region") >= 0, "region retains native picker")
        check(panel.captureMode === "screenshot" && !host.desktopAudio && !host.microphoneAudio, "initial state")
        panel.setCursor("mode", 1); panel.activateCursor()
        check(host.captureMode === "record" && host.captured === "", "tab changes mode without capturing")
        check(panel.visibleSections.indexOf("audio") >= 0, "audio in record navigation")
        panel.setCursor("audio", 0); panel.activateCursor()
        check(host.desktopAudio && !host.microphoneAudio, "independent desktop toggle")
        panel.moveCursor(1); panel.activateCursor()
        check(host.desktopAudio && host.microphoneAudio, "independent microphone toggle")
        check(panel.showMicrophonePicker, "multiple inputs show picker")
        panel.setCursor("microphone", 2); panel.activateCursor()
        check(host.selectedMicrophone === "usb", "keyboard microphone selection")
        panel.moveCursor(-1)
        check(panel.selectedIndex === 1, "microphone list vertical navigation")
        host.microphoneInputs = [{name: "usb", label: "USB headset"}]
        check(!panel.showMicrophonePicker && panel.visibleSections.indexOf("microphone") < 0, "single input hides picker")
        host.microphoneInputs = []
        check(!panel.showMicrophonePicker, "zero inputs hides picker")
        host.microphoneInputs = [{name: "onboard", label: "Onboard"}, {name: "usb", label: "USB headset"}]
        host.microphoneAudio = false
        check(!panel.showMicrophonePicker, "disabled microphone hides picker")
        host.microphoneAudio = true
        panel.setCursor("target", 2); panel.activateCursor()
        check(!panel.canStart, "monitor requires selection")
        panel.setCursor("capture", 0); panel.activateCursor()
        check(host.captured === "", "missing monitor blocks capture")
        panel.setCursor("monitor", 1); panel.activateCursor()
        check(panel.canStart && host.selectedMonitor === "DP-2", "monitor selection")
        panel.setCursor("capture", 0); panel.activateCursor()
        check(host.captured === "record", "record action")
        host.captured = ""
        panel.setCursor("mode", 0); panel.activateCursor()
        check(panel.visibleSections.indexOf("audio") < 0, "audio hidden for screenshots")
        panel.setCursor("capture", 0); panel.activateCursor()
        check(host.captured === "screenshot", "screenshot action")
        panel.tabCursor(1)
        check(panel.focusSection === "mode" && panel.selectedIndex === 0, "tab wraps")
        panel.tabCursor(-1)
        check(panel.focusSection === "capture", "shift tab wraps")
        for (var desktop = 0; desktop < 2; desktop++) {
          for (var microphone = 0; microphone < 2; microphone++) {
            widget.desktopAudio = !!desktop; widget.microphoneAudio = !!microphone
            var expected = desktop ? (microphone ? "default_output|default_input" : "default_output") : (microphone ? "default_input" : "")
            check(widget.recordingAudioSource() === expected, "audio mapping " + desktop + microphone)
          }
        }
        widget.updateMicrophones(JSON.stringify([{name: "usb", description: "USB headset"}, {name: "speakers.monitor"}]))
        check(widget.microphoneInputs.length === 1, "exclude output monitors")
        widget.setSelectedMicrophone("usb")
        widget.microphoneAudio = true; widget.desktopAudio = false
        check(widget.recordingAudioSource() === "device:usb", "specific microphone argument")
        widget.desktopAudio = true
        check(widget.recordingAudioSource() === "default_output|device:usb", "mix selected microphone")
        widget.setSelectedMicrophone("missing")
        check(widget.selectedMicrophone === "usb", "reject unknown selection")
        widget.updateMicrophones("[]")
        check(widget.selectedMicrophone === "" && widget.microphoneMessage.indexOf("disconnected") >= 0, "unplug resets selection with notice")
        console.log("PASS tabs, toggles, monitor gating, capture, keyboard navigation, four audio modes")
      } catch (error) {
        console.error(String(error))
      }
      finish.start()
    }
  }
  Timer { id: finish; interval: 100; onTriggered: Qt.quit() }
}
