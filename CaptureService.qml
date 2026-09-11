pragma Singleton
import QtQuick

Item {
  id: root
  property string captureMode: "screenshot"
  property string targetType: "region"
  property bool desktopAudio: false
  property bool microphoneAudio: false
  property string selectedMonitor: ""
  property string selectedMicrophone: ""
  property var monitors: []
  property var microphoneInputs: []
  property string microphoneMessage: ""
  property string errorMessage: ""
  property string lastSaved: ""
  property string shareUrl: ""
  property string shareError: ""
  property bool share: false
  property string shareServer: ""
  property string shareToken: ""
  readonly property bool configLoading: configProcess.running
  property string phase: "idle"
  property double recordingStartTime: 0
  property int elapsedSeconds: 0
  property var consumers: ({})
  property var panels: ({})
  property int nextConsumer: 0
  property var pendingRequest: null
  property bool readyToLaunch: false
  property int microphoneFailures: 0
  property bool gotMicrophones: false
  property bool gotMonitors: false
  property bool captureOutcome: false
  readonly property bool active: Object.keys(consumers).length > 0
  readonly property bool panelVisible: Object.keys(panels).length > 0
  readonly property bool recording: phase === "recording" || phase === "stopping"
  readonly property bool microphoneLoading: microphonesProcess.running
  readonly property bool canStart: phase === "idle" && (targetType !== "monitor" || monitors.some(function(m) { return m.name === root.selectedMonitor }))
  readonly property string elapsedTimeText: {
    var m = Math.floor(elapsedSeconds / 60), s = elapsedSeconds % 60
    return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
  }
  signal captureRequested()

  function acquire() {
    var token = String(++nextConsumer), next = Object.assign({}, consumers)
    next[token] = true; consumers = next
    return token
  }
  function release(token) {
    if (!Object.prototype.hasOwnProperty.call(consumers, token)) return
    var next = Object.assign({}, consumers); delete next[token]; consumers = next
    setPanelVisible(token, false)
    if (active) return
    pendingRequest = null
    readyToLaunch = false
    fadeDelay.stop()
    monitorsProcess.cancel(); microphonesProcess.cancel(); captureProcess.cancel(); configProcess.cancel()
    phase = "idle"
  }
  function setPanelVisible(token, visible) {
    var next = Object.assign({}, panels)
    if (visible && consumers[token]) next[token] = true
    else delete next[token]
    panels = next
    if (visible) {
      microphoneFailures = 0
      refreshMonitors(); refreshMicrophones()
    }
  }
  function setTargetType(value) {
    if (["region", "app", "monitor"].indexOf(value) < 0 || phase !== "idle") return
    targetType = value
    if (value === "monitor" && monitors.length === 1) selectedMonitor = monitors[0].name
  }
  function setSelectedMonitor(value) {
    if (phase === "idle" && monitors.some(function(m) { return m.name === value })) selectedMonitor = value
  }
  function setSelectedMicrophone(value) {
    if (phase !== "idle") return
    if (value === "" || microphoneInputs.some(function(m) { return m.name === value })) {
      selectedMicrophone = value; microphoneMessage = ""
    }
  }
  function refreshMonitors() {
    if (!active || !panelVisible || monitorsProcess.running) return
    gotMonitors = false
    monitorsProcess.launch("monitors", null)
  }
  function refreshMicrophones() {
    if (!active || !panelVisible || microphonesProcess.running || microphoneFailures >= 4) return
    gotMicrophones = false
    microphonesProcess.launch("microphones", null)
  }
  onMicrophoneAudioChanged: if (microphoneAudio) { microphoneFailures = 0; refreshMicrophones() }
  onCaptureModeChanged: if (captureMode === "record") { microphoneFailures = 0; refreshMicrophones() }

  function startCapture(action) {
    if (!active || !panelVisible || !canStart || ["screenshot", "record"].indexOf(action) < 0) return false
    pendingRequest = {action: action, target: targetType, monitor: selectedMonitor,
      desktop: action === "record" && desktopAudio, microphone: action === "record" && microphoneAudio,
      input: action === "record" && microphoneAudio ? selectedMicrophone : "",
      share: action === "screenshot" && share}
    errorMessage = ""
    captureOutcome = false
    phase = "preparing"
    readyToLaunch = false
    captureRequested()
    if (captureProcess.running) captureProcess.cancel() // Previous clipboard owner.
    fadeDelay.restart()
    return true
  }
  function launchPending() {
    if (!pendingRequest || !readyToLaunch || captureProcess.running || !active) return
    var data = pendingRequest
    pendingRequest = null
    captureProcess.launch("capture", data)
  }
  function loadConfig() {
    if (!active || configProcess.running) return
    configProcess.launch("config", {server: "", token: ""})
  }
  function saveConfig(server, token) {
    if (!active || configProcess.running) return false
    configProcess.launch("config", {server: server, token: token})
    return true
  }
  function stopRecording() {
    if (phase !== "recording") return
    phase = "stopping"
    captureProcess.stopRecording()
  }
  function cancelCapture() {
    pendingRequest = null
    readyToLaunch = false
    fadeDelay.stop()
    captureProcess.cancel()
    phase = "idle"
  }
  BackendProcess {
    id: monitorsProcess
    onMessage: function(data) {
      if (!root.active) return
      if (data.event === "monitors") {
        gotMonitors = true
        monitors = data.items
        if (monitors.length === 1) selectedMonitor = monitors[0].name
        else if (!monitors.some(function(m) { return m.name === root.selectedMonitor })) selectedMonitor = ""
      } else if (data.event === "error") errorMessage = data.message
    }
    onFinished: function(code) {
      if (root.active && !gotMonitors) { monitors = []; selectedMonitor = ""; errorMessage = "Could not refresh monitors" }
    }
  }
  BackendProcess {
    id: microphonesProcess
    onMessage: function(data) {
      if (!root.active) return
      if (data.event === "microphones") {
        gotMicrophones = true
        microphoneFailures = 0
        if (JSON.stringify(microphoneInputs) !== JSON.stringify(data.items)) microphoneInputs = data.items
        if (selectedMicrophone && !microphoneInputs.some(function(m) { return m.name === root.selectedMicrophone })) {
          selectedMicrophone = ""
          microphoneMessage = "Selected microphone disconnected. Using system default."
        } else if (!microphoneInputs.length) microphoneMessage = "No microphone inputs found."
        else if (microphoneMessage.indexOf("disconnected") < 0) microphoneMessage = ""
      } else if (data.event === "error") microphoneMessage = data.message
    }
    onFinished: function(code) {
      if (root.active && !gotMicrophones) {
        microphoneFailures++
        microphoneMessage = "Could not refresh microphone inputs. Reopen the dialog to retry."
      }
    }
  }
  BackendProcess {
    id: captureProcess
    onMessage: function(data) {
      if (!root.active || pendingRequest) return
      if (data.event === "phase") {
        if (data.phase === "recording") { recordingStartTime = Date.now(); elapsedSeconds = 0 }
        phase = data.phase === "clipboard" ? "idle" : data.phase
      } else if (data.event === "saved") {
        captureOutcome = true
        lastSaved = data.name
        errorMessage = data.warning
        phase = "idle"
      } else if (data.event === "shared") {
        shareUrl = data.url
        shareError = ""
      } else if (data.event === "share_error") {
        shareUrl = ""
        shareError = data.message
      } else if (data.event === "cancelled") {
        captureOutcome = true
        phase = "idle"
      } else if (data.event === "error") {
        captureOutcome = true
        errorMessage = data.message
        phase = "idle"
      }
    }
    onFinished: function(code) {
      if (pendingRequest) { Qt.callLater(root.launchPending); return }
      if (root.active && !captureOutcome) errorMessage = "Capture helper exited before completing"
      phase = "idle"
    }
  }
  Timer { id: fadeDelay; interval: 200; onTriggered: { root.readyToLaunch = true; root.launchPending() } }
  Timer {
    interval: 3000 * Math.pow(2, root.microphoneFailures)
    running: root.active && root.panelVisible && root.captureMode === "record" && root.microphoneAudio && root.microphoneFailures < 4
    repeat: true
    onTriggered: root.refreshMicrophones()
  }
  Timer {
    interval: 250
    repeat: true
    running: root.recording
    onTriggered: root.elapsedSeconds = Math.max(0, Math.floor((Date.now() - root.recordingStartTime) / 1000))
  }
  BackendProcess {
    id: configProcess
    onMessage: function(data) {
      if (!root.active) return
      if (data.event === "config") {
        root.shareServer = data.server
        root.shareToken = data.token
      } else if (data.event === "error") {
        root.shareError = data.message
      }
    }
    onFinished: function(code) {
      if (!root.active) return
      if (code !== 0 && root.shareError === "") root.shareError = "Could not configure share settings"
    }
  }
  Component.onDestruction: { monitorsProcess.cancel(); microphonesProcess.cancel(); captureProcess.cancel(); configProcess.cancel() }
}
