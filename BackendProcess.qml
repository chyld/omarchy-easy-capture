import QtQuick
import Quickshell
import Quickshell.Io
import "CaptureModel.js" as Model

Item {
  id: root
  property string operation: ""
  property var request: null
  property string buffer: ""
  property int collected: 0
  property bool rejected: false
  readonly property bool running: process.running
  signal message(var data)
  signal finished(int code)

  function environment() {
    var env = {"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}
    var keys = ["HOME", "XDG_RUNTIME_DIR", "HYPRLAND_INSTANCE_SIGNATURE", "WAYLAND_DISPLAY", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS",
                "XDG_CONFIG_HOME", "XDG_PICTURES_DIR", "XDG_VIDEOS_DIR", "OMARCHY_SCREENSHOT_DIR", "OMARCHY_SCREENRECORD_DIR"]
    for (var i = 0; i < keys.length; i++) {
      var value = Quickshell.env(keys[i])
      if (value && value.length <= 4096 && !/[\x00-\x1f\x7f]/.test(value)) env[keys[i]] = value
    }
    return env
  }
  function launch(op, payload) {
    if (running || ["monitors", "microphones", "capture"].indexOf(op) < 0) return false
    operation = op
    request = payload || null
    buffer = ""
    collected = 0
    rejected = false
    process.stdinEnabled = true
    process.running = true
    deadline.restart()
    return true
  }
  function stopRecording() { if (running) process.write("stop\n") }
  function cancel() {
    if (!running) return
    rejected = true
    process.signal(15)
    escalation.restart()
  }
  function fail() {
    message({event: "error", message: "Capture helper returned an invalid response"})
    cancel()
  }
  function collect(chunk) {
    if (rejected) return
    if (collected + chunk.length > 131072 || buffer.length + chunk.length > 32768) { fail(); return }
    collected += chunk.length
    buffer += chunk
    var at
    while ((at = buffer.indexOf("\n")) >= 0) {
      var line = buffer.substring(0, at)
      buffer = buffer.substring(at + 1)
      try { message(Model.event(line)) }
      catch (e) { fail(); return }
    }
  }
  Component.onDestruction: if (process.running) process.signal(15)

  Process {
    id: process
    command: ["/usr/bin/python3", "-I", "-S", "-B",
      decodeURIComponent(Qt.resolvedUrl("./capture_backend.py").toString().replace(/^file:\/\//, "")), root.operation]
    clearEnvironment: true
    environment: root.environment()
    stdinEnabled: true
    stdout: SplitParser { splitMarker: ""; onRead: function(chunk) { root.collect(chunk) } }
    stderr: SplitParser { splitMarker: ""; onRead: function(chunk) {} }
    onStarted: if (root.operation === "capture") process.write(JSON.stringify(root.request) + "\n")
    onExited: function(code) {
      deadline.stop()
      escalation.stop()
      if (!root.rejected && root.buffer !== "") root.fail()
      root.buffer = ""
      root.finished(code)
    }
  }
  Timer {
    id: deadline
    interval: root.operation === "capture" ? 29100000 : 10000
    onTriggered: {
      root.message({event: "error", message: "Capture helper timed out"})
      root.cancel()
    }
  }
  Timer { id: escalation; interval: 8000; onTriggered: if (process.running) process.signal(9) }
}
