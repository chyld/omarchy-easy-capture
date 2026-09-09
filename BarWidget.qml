import QtQuick
import QtQuick.Shapes
import "AudioDevices.js" as AudioDevices
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Easy Capture: the bar icon, all state, and every action. CapturePanel.qml
// is a pure view injected with this widget as hostWidget -- it only reads
// state and calls back into the functions here.
//
// Region picking uses omarchy-capture-region. App picking uses our local
// copy, capture-region.sh, to include visible windows on every monitor:
// "region" mode is a freeform drag, "windows" mode highlights window/monitor
// rects and snaps to whichever one is clicked. --match-monitor reports a
// snap that exactly covers a monitor as "monitor:NAME" so it can be captured
// at full native resolution instead of as a region. Monitor target type
// skips picking entirely -- monitors are enumerable up front from
// `hyprctl monitors -j`, so there's nothing to click on screen.
BarWidget {
  id: root
  moduleName: "chyld.easy-capture"

  // ---- picker state, read by CapturePanel -----------------------------

  property string captureMode: "screenshot"
  property bool desktopAudio: false
  property bool microphoneAudio: false
  property string pendingAudioSource: ""
  property var microphoneInputs: []
  property string selectedMicrophone: ""
  property string microphoneMessage: ""
  readonly property bool microphoneLoading: microphoneProcess.running

  onMicrophoneAudioChanged: if (microphoneAudio) refreshMicrophones()
  onCaptureModeChanged: if (captureMode === "record") refreshMicrophones()

  property string targetType: "region" // "region" | "app" | "monitor"
  property string selectedMonitor: ""
  property var monitors: [] // [{name, width, height}]
  readonly property bool canStart: root.targetType !== "monitor" || root.selectedMonitor !== ""

  // idle -> picking -> (screenshotting | starting -> recording -> stopping) -> idle
  property string phase: "idle"
  property string pendingAction: "" // "screenshot" | "record", set while picking
  property string freezePid: ""
  property var recordingStartTime: null
  property int elapsedSeconds: 0

  readonly property bool recording: root.phase === "recording" || root.phase === "stopping"
  readonly property string elapsedTimeText: {
    var total = Math.max(0, root.elapsedSeconds)
    var m = Math.floor(total / 60)
    var s = total % 60
    var mm = m < 10 ? "0" + m : "" + m
    var ss = s < 10 ? "0" + s : "" + s
    return mm + ":" + ss
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  // ---- panel lifecycle (mirrors the summonBarWidget contract: open/close/opened) --

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    root.refreshMonitors()
    root.refreshMicrophones()
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function togglePanel() {
    if (!panelLoader.item) return
    if (panelLoader.item.opened) root.close()
    else root.open()
  }

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("CapturePanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
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
      tooltipText: root.recording ? "Recording · click to stop" : "Easy Capture"

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
        if (root.phase === "recording") root.stopRecording()
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

  // ---- monitor list, queried fresh each time the panel opens ---------------

  Process {
    id: monitorsProcess
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      id: monitorsCollector
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.monitors = []
        return
      }
      try {
        var data = JSON.parse(monitorsCollector.text)
        var list = []
        for (var i = 0; i < data.length; i++)
          list.push({ name: data[i].name, width: data[i].width, height: data[i].height })
        root.monitors = list
        if (list.length === 1) {
          root.selectedMonitor = list[0].name
        } else {
          var stillPresent = false
          for (var j = 0; j < list.length; j++)
            if (list[j].name === root.selectedMonitor) stillPresent = true
          if (!stillPresent) root.selectedMonitor = ""
        }
      } catch (e) {
        root.monitors = []
      }
    }
  }

  function refreshMonitors() {
    monitorsProcess.running = true
  }

  function updateMicrophones(text) {
    var inputs = AudioDevices.parseInputs(text)
    if (JSON.stringify(inputs) !== JSON.stringify(root.microphoneInputs)) root.microphoneInputs = inputs
    var present = root.selectedMicrophone === ""
    for (var i = 0; i < inputs.length; i++)
      if (inputs[i].name === root.selectedMicrophone) present = true
    if (!present) {
      root.selectedMicrophone = ""
      root.microphoneMessage = "Selected microphone disconnected. Using system default."
    } else if (inputs.length === 0) {
      root.microphoneMessage = "No microphone inputs found."
    } else if (root.microphoneMessage !== "Selected microphone disconnected. Using system default.") {
      root.microphoneMessage = ""
    }
  }

  function setSelectedMicrophone(name) {
    if (name !== "") {
      var present = false
      for (var i = 0; i < root.microphoneInputs.length; i++)
        if (root.microphoneInputs[i].name === name) present = true
      if (!present) return
    }
    root.selectedMicrophone = name
    root.microphoneMessage = ""
  }

  function refreshMicrophones() {
    if (!microphoneProcess.running) microphoneProcess.running = true
  }

  Process {
    id: microphoneProcess
    command: ["pactl", "--format=json", "list", "sources"]
    stdout: StdioCollector { id: microphoneCollector; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.microphoneMessage = "Could not refresh microphone inputs."
        return
      }
      try { root.updateMicrophones(microphoneCollector.text) }
      catch (e) { root.microphoneMessage = "Could not read microphone inputs." }
    }
  }

  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.captureMode === "record" && root.microphoneAudio
    onTriggered: root.refreshMicrophones()
  }

  function setTargetType(type) {
    root.targetType = type
    if (type === "monitor" && root.monitors.length === 1)
      root.selectedMonitor = root.monitors[0].name
  }

  function setSelectedMonitor(name) {
    root.selectedMonitor = name
  }

  // ---- kick off a capture from the panel ------------------------------

  property string pendingStartAction: ""

  function startCapture(action) {
    if (!root.canStart || root.phase !== "idle" || closeFadeTimer.running) return
    if (action !== "screenshot" && action !== "record") return
    root.pendingAudioSource = action === "record" ? root.recordingAudioSource() : ""
    root.close()
    root.pendingStartAction = action
    // The popup fades out over 140ms (KeyboardPanel's own close animation)
    // and stays mapped/composited the whole time. Freezing the screen or
    // grabbing a monitor screenshot right after close() -- with no delay --
    // catches it mid-fade, so it shows up in the capture. Waiting past the
    // animation (with a small margin) lets it actually finish unmapping
    // first.
    closeFadeTimer.restart()
  }

  Timer {
    id: closeFadeTimer
    interval: 200
    repeat: false
    onTriggered: root.afterPanelClosed()
  }

  function pickerCommand(mode) {
    if (mode === "windows") {
      var helper = decodeURIComponent(Qt.resolvedUrl("./capture-region.sh").toString().replace(/^file:\/\//, ""))
      return ["bash", helper, "windows", "--match-monitor", "--keep-freeze"]
    }
    return ["bash", "-c", "exec \"$@\" </dev/null", "bash", "omarchy-capture-region", mode, "--match-monitor", "--keep-freeze"]
  }

  function afterPanelClosed() {
    var action = root.pendingStartAction
    root.pendingStartAction = ""

    if (root.targetType === "monitor") {
      root.executeAction(action, "monitor", root.selectedMonitor)
      return
    }

    root.pendingAction = action
    root.phase = "picking"
    var mode = root.targetType === "app" ? "windows" : "region"
    pickProcess.pickedLines = []
    // "region" mode reads slurp's stdin directly, and Quickshell's Process
    // leaves a spawned child's stdin connected to a pipe that never sends
    // EOF -- slurp then blocks reading it before it ever maps its overlay,
    // so nothing visibly happens. "windows" mode never hit this because its
    // own script pipes `get_rectangles` into slurp, which replaces stdin
    // with something that closes normally. Redirecting from /dev/null here
    // sidesteps the problem for both modes.
    pickProcess.command = root.pickerCommand(mode)
    pickProcess.running = true
  }

  function killFreeze() {
    if (root.freezePid) {
      killFreezeProcess.command = ["kill", root.freezePid]
      killFreezeProcess.running = true
      root.freezePid = ""
    }
  }

  function executeAction(action, kind, value) {
    if (action === "screenshot") root.runScreenshotFor(kind, value)
    else root.runRecordingFor(kind, value)
  }

  Process {
    id: pickProcess
    property var pickedLines: []
    // Bounded: the helper only ever emits a freeze PID line and a selection
    // line, so lines past the first two are ignored rather than buffered.
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (pickProcess.pickedLines.length < 2)
          pickProcess.pickedLines.push(data)
      }
    }
    onExited: function(exitCode) {
      var lines = pickProcess.pickedLines
      root.freezePid = lines.length > 0 ? lines[0] : ""
      var selection = lines.length > 1 ? lines[1] : ""

      if (!selection) {
        root.killFreeze()
        root.phase = "idle"
        root.pendingAction = ""
        return
      }

      var monitorMatch = selection.match(/^monitor:(.+)$/)
      var action = root.pendingAction
      root.pendingAction = ""
      if (monitorMatch) root.executeAction(action, "monitor", monitorMatch[1])
      else root.executeAction(action, "rect", selection)
    }
  }

  Process {
    id: killFreezeProcess
  }

  // ---- screenshot -----------------------------------------------------

  readonly property string screenshotScriptRegion: [
    "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs",
    "OUTPUT_DIR=\"${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}\"",
    "mkdir -p \"$OUTPUT_DIR\"",
    "FILEPATH=\"$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png\"",
    "grim -g \"$1\" \"$FILEPATH\" || exit 1",
    "wl-copy --type image/png <\"$FILEPATH\"",
    "omarchy-notification-send \"Screenshot saved to clipboard and file\" \"$FILEPATH\" --image \"$FILEPATH\""
  ].join("\n")

  readonly property string screenshotScriptMonitor: [
    "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs",
    "OUTPUT_DIR=\"${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}\"",
    "mkdir -p \"$OUTPUT_DIR\"",
    "FILEPATH=\"$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png\"",
    "grim -o \"$1\" \"$FILEPATH\" || exit 1",
    "wl-copy --type image/png <\"$FILEPATH\"",
    "omarchy-notification-send \"Screenshot saved to clipboard and file\" \"$FILEPATH\" --image \"$FILEPATH\""
  ].join("\n")

  function runScreenshotFor(kind, value) {
    root.phase = "screenshotting"
    root.killFreeze()
    var script = kind === "monitor" ? root.screenshotScriptMonitor : root.screenshotScriptRegion
    // Passed as $1, never interpolated into the script text, so the target
    // value can't be read as shell syntax.
    screenshotProcess.command = ["bash", "-c", script, "bash", value]
    screenshotProcess.running = true
  }

  Process {
    id: screenshotProcess
    onExited: function(exitCode) {
      root.phase = "idle"
    }
  }

  // ---- record -----------------------------------------------------------

  // gpu-screen-recorder's -w takes a monitor name as-is, but for a region or
  // window rect it wants "WxH+X+Y" -- not slurp's "X,Y WxH" -- so that needs
  // reformatting before it's usable here. grim (screenshots) keeps the
  // original slurp string, so this conversion is record-only.
  function regionToGsrFormat(selection) {
    var m = selection.match(/^(-?\d+),(-?\d+)\s(\d+)x(\d+)$/)
    if (!m) return selection
    return m[3] + "x" + m[4] + "+" + m[1] + "+" + m[2]
  }

  function recordingAudioSource() {
    var sources = []
    if (root.desktopAudio) sources.push("default_output")
    if (root.microphoneAudio) sources.push(root.selectedMicrophone ? "device:" + root.selectedMicrophone : "default_input")
    return sources.join("|")
  }

  readonly property string recordScript: [
    "[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs",
    "OUTPUT_DIR=\"${OMARCHY_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}\"",
    "mkdir -p \"$OUTPUT_DIR\"",
    "FILEPATH=\"$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4\"",
    "CAPTURE_ARGS=(-w \"$2\")",
    "if [[ \"$1\" == monitor ]]; then",
    "  read -r MON_W MON_H < <(hyprctl monitors -j | jq -r --arg name \"$2\" '.[] | select(.name == $name) | \"\\(.width) \\(.height)\"')",
    "  if [[ -n $MON_W ]] && { (( MON_W > 3840 )) || (( MON_H > 2160 )); }; then",
    "    CAPTURE_ARGS+=(-s 3840x2160)",
    "  else",
    "    CAPTURE_ARGS+=(-s 0x0)",
    "  fi",
    "fi",
    "AUDIO_ARGS=()",
    "[[ -n $3 ]] && AUDIO_ARGS=(-a \"$3\" -ac aac)",
    "gpu-screen-recorder \"${CAPTURE_ARGS[@]}\" \"${AUDIO_ARGS[@]}\" -k auto -f 60 -fm cfr -fallback-cpu-encoding yes -o \"$FILEPATH\" &",
    "PID=$!",
    "while kill -0 $PID 2>/dev/null && [[ ! -f $FILEPATH ]]; do sleep 0.1; done",
    "if ! kill -0 $PID 2>/dev/null; then",
    "  echo FAILED",
    "  omarchy-notification-send -u critical \"Screen recording failed to start\" \"gpu-screen-recorder exited immediately\"",
    "  exit 1",
    "fi",
    "echo STARTED",
    "wait $PID",
    "[[ -f $FILEPATH ]] && omarchy-notification-send \"Screen recording saved\" \"$FILEPATH\" --exec mpv -- \"$FILEPATH\""
  ].join("\n")

  function runRecordingFor(kind, value) {
    root.phase = "starting"
    root.killFreeze()
    var gsrTarget = kind === "rect" ? root.regionToGsrFormat(value) : value
    recordProcess.command = ["bash", "-c", root.recordScript, "bash", kind, gsrTarget, root.pendingAudioSource]
    recordProcess.running = true
  }

  function stopRecording() {
    if (root.phase !== "recording")
      return
    root.phase = "stopping"
    // SIGINT (not TERM/KILL) so gpu-screen-recorder finalizes the container
    // properly, matching omarchy-capture-screenrecording's own stop path.
    // recordProcess's own onExited drives the return to idle once the
    // recorder has actually finished writing the file.
    stopProcess.command = ["pkill", "-SIGINT", "-f", "^gpu-screen-recorder"]
    stopProcess.running = true
  }

  Process {
    id: stopProcess
  }

  Process {
    id: recordProcess
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        if (data === "STARTED") {
          root.recordingStartTime = Date.now()
          root.elapsedSeconds = 0
          root.phase = "recording"
          elapsedTimer.start()
        } else if (data === "FAILED") {
          root.phase = "idle"
        }
      }
    }
    onExited: function(exitCode) {
      elapsedTimer.stop()
      root.recordingStartTime = null
      root.phase = "idle"
    }
  }

  Timer {
    id: elapsedTimer
    interval: 250
    repeat: true
    onTriggered: {
      if (root.recordingStartTime)
        root.elapsedSeconds = Math.floor((Date.now() - root.recordingStartTime) / 1000)
    }
  }

}
