import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "chyld.easy-capture"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  readonly property string captureMode: hostWidget ? hostWidget.captureMode : "screenshot"
  readonly property string targetType: hostWidget ? hostWidget.targetType : "region"
  readonly property var monitorList: hostWidget ? hostWidget.monitors : []
  readonly property string selectedMonitor: hostWidget ? hostWidget.selectedMonitor : ""
  readonly property var microphoneInputs: hostWidget ? hostWidget.microphoneInputs : []
  readonly property bool showMicrophones: captureMode === "record" && hostWidget && hostWidget.microphoneAudio
  readonly property bool showMicrophonePicker: showMicrophones && microphoneInputs.length > 1
  readonly property var microphoneOptions: [{name: "", label: "System default"}].concat(microphoneInputs)
  readonly property bool canStart: hostWidget ? hostWidget.canStart && hostWidget.phase === "idle" : false
  readonly property bool showMonitorList: targetType === "monitor" && monitorList.length !== 1
  readonly property string panelFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var targetValues: ["region", "app", "monitor"]
  readonly property var modeValues: ["screenshot", "record"]
  property string focusSection: "mode"
  property int selectedIndex: 0
  readonly property var visibleSections: {
    var sections = ["mode", "target"]
    if (showMonitorList && monitorList.length) sections.push("monitor")
    if (captureMode === "record") sections.push("audio")
    if (showMicrophonePicker) sections.push("microphone")
    sections.push("capture")
    return sections
  }

  function setCursor(section, index) {
    focusSection = section
    selectedIndex = index
  }
  function sectionCount(section) {
    if (section === "mode" || section === "audio") return 2
    if (section === "target") return 3
    if (section === "monitor") return monitorList.length
    if (section === "microphone") return microphoneOptions.length
    return 1
  }
  function normalizeCursor() {
    if (visibleSections.indexOf(focusSection) < 0) setCursor("target", 0)
    selectedIndex = Math.max(0, Math.min(selectedIndex, sectionCount(focusSection) - 1))
  }
  onVisibleSectionsChanged: normalizeCursor()
  onMonitorListChanged: normalizeCursor()
  onMicrophoneInputsChanged: normalizeCursor()
  onOpenedChanged: if (opened) setCursor("mode", modeValues.indexOf(captureMode))

  function moveCursor(dy) {
    var vertical = focusSection === "monitor" || focusSection === "audio" || focusSection === "microphone"
    var next = selectedIndex + dy
    if (vertical && next >= 0 && next < sectionCount(focusSection)) {
      selectedIndex = next
      return
    }
    var section = visibleSections.indexOf(focusSection) + dy
    if (section >= 0 && section < visibleSections.length) {
      var name = visibleSections[section]
      setCursor(name, dy > 0 ? 0 : sectionCount(name) - 1)
    }
  }
  function moveCursorH(dx) {
    if (focusSection !== "mode" && focusSection !== "target") return
    selectedIndex = Math.max(0, Math.min(selectedIndex + dx, sectionCount(focusSection) - 1))
  }
  function tabCursor(direction) {
    var index = selectedIndex + direction
    if (index >= 0 && index < sectionCount(focusSection)) selectedIndex = index
    else {
      var section = (visibleSections.indexOf(focusSection) + direction + visibleSections.length) % visibleSections.length
      var name = visibleSections[section]
      setCursor(name, direction > 0 ? 0 : sectionCount(name) - 1)
    }
  }
  function toggleAudio(index) {
    if (!hostWidget) return
    if (index === 0) hostWidget.desktopAudio = !hostWidget.desktopAudio
    else hostWidget.microphoneAudio = !hostWidget.microphoneAudio
  }
  function activateCursor() {
    if (!hostWidget) return
    if (focusSection === "mode") hostWidget.captureMode = modeValues[selectedIndex]
    else if (focusSection === "target") hostWidget.setTargetType(targetValues[selectedIndex])
    else if (focusSection === "monitor" && monitorList[selectedIndex]) hostWidget.setSelectedMonitor(monitorList[selectedIndex].name)
    else if (focusSection === "audio") toggleAudio(selectedIndex)
    else if (focusSection === "microphone" && microphoneOptions[selectedIndex]) hostWidget.setSelectedMicrophone(microphoneOptions[selectedIndex].name)
    else if (focusSection === "capture" && canStart) hostWidget.startCapture(captureMode)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onMoveRequested: function(dx, dy) {
        if (dx) root.moveCursorH(dx)
        if (dy) root.moveCursor(dy)
      }
      onTabRequested: function(direction) { root.tabCursor(direction) }
      onActivateRequested: root.activateCursor()

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)
        Text {
          text: "Easy Capture"
          textFormat: Text.PlainText
          color: root.barForeground
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.body * 0.9
          font.bold: true
        }
        CaptureButtonGroup {
          objectName: "modeTabs"
          width: parent.width
          equalWidth: true
          fontFamily: root.panelFontFamily
          foreground: root.barForeground
          options: [{value: "screenshot", label: "Screenshot", icon: ""}, {value: "record", label: "Record", icon: ""}]
          value: root.captureMode
          cursorIndex: root.focusSection === "mode" ? root.selectedIndex : -1
          onHovered: function(index, hovered) { if (hovered) root.setCursor("mode", index) }
          onChanged: function(value) {
            root.setCursor("mode", root.modeValues.indexOf(value))
            if (root.hostWidget) root.hostWidget.captureMode = value
          }
        }
        Column {
          width: parent.width
          spacing: Style.space(6)
          PanelSectionHeader { fontSize: Style.font.caption * 0.9; text: "target"; foreground: root.barForeground }
          CaptureButtonGroup {
            objectName: "targetButtons"
            width: parent.width
            equalWidth: true
            fontFamily: root.panelFontFamily
            foreground: root.barForeground
            options: [{value: "region", label: "Region", icon: "󰆟"}, {value: "app", label: "App", icon: "󰖯"}, {value: "monitor", label: "Monitor", icon: "󰍹"}]
            value: root.targetType
            cursorIndex: root.focusSection === "target" ? root.selectedIndex : -1
            onHovered: function(index, hovered) { if (hovered) root.setCursor("target", index) }
            onChanged: function(value) {
              root.setCursor("target", root.targetValues.indexOf(value))
              if (root.hostWidget) root.hostWidget.setTargetType(value)
            }
          }
          Column {
            visible: root.showMonitorList
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.monitorList
              delegate: CaptureButton {
                required property var modelData
                required property int index
                width: parent.width
                leftAlign: true
                fontFamily: root.panelFontFamily
                foreground: root.barForeground
                iconText: "󰍹"
                text: modelData.name
                selected: root.selectedMonitor === modelData.name
                hasCursor: root.focusSection === "monitor" && root.selectedIndex === index
                onHovered: function(hovered) { if (hovered) root.setCursor("monitor", index) }
                onClicked: if (root.hostWidget) root.hostWidget.setSelectedMonitor(modelData.name)
              }
            }
            Text {
              visible: root.monitorList.length === 0
              text: "No monitors found"
              color: root.barForeground
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.bodySmall * 0.9
            }
          }
        }
        Column {
          objectName: "audioOptions"
          visible: root.captureMode === "record"
          width: parent.width
          spacing: Style.space(6)
          PanelSectionHeader { fontSize: Style.font.caption * 0.9; text: "audio"; foreground: root.barForeground }
          Repeater {
            model: ["Desktop sounds", "Microphone"]
            delegate: CaptureButton {
              required property string modelData
              required property int index
              readonly property bool checked: root.hostWidget ? (index === 0 ? root.hostWidget.desktopAudio : root.hostWidget.microphoneAudio) : false
              objectName: index === 0 ? "desktopToggle" : "microphoneToggle"
              width: parent.width
              leftAlign: true
              text: modelData + " · " + (checked ? "On" : "Off")
              iconText: index === 0 ? (checked ? "" : "") : (checked ? "󰍬" : "󰍭")
              iconColor: checked ? Style.selectedStateColor(root.barForeground, Color.accent) : Color.urgent
              selected: checked
              fontFamily: root.panelFontFamily
              foreground: root.barForeground
              hasCursor: root.focusSection === "audio" && root.selectedIndex === index
              onHovered: function(hovered) { if (hovered) root.setCursor("audio", index) }
              onClicked: root.toggleAudio(index)
            }
          }
        }
        Column {
          objectName: "microphonePicker"
          visible: root.showMicrophones
          width: parent.width
          spacing: Style.space(6)
          PanelSectionHeader {
            visible: root.showMicrophonePicker
            fontSize: Style.font.caption * 0.9
            text: "microphone input"
            foreground: root.barForeground
          }
          Column {
            visible: root.showMicrophonePicker
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.microphoneOptions
              delegate: CaptureButton {
                required property var modelData
                required property int index
                width: parent.width
                leftAlign: true
                text: modelData.label
                selected: root.hostWidget && root.hostWidget.selectedMicrophone === modelData.name
                fontFamily: root.panelFontFamily
                foreground: root.barForeground
                hasCursor: root.focusSection === "microphone" && root.selectedIndex === index
                onHovered: function(hovered) { if (hovered) root.setCursor("microphone", index) }
                onClicked: if (root.hostWidget) root.hostWidget.setSelectedMicrophone(modelData.name)
              }
            }
          }
          Text {
            visible: !root.showMicrophonePicker && root.microphoneInputs.length === 1
            width: parent.width
            text: root.microphoneInputs.length ? root.microphoneInputs[0].label : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.barForeground
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall * 0.9
          }
          Text {
            visible: text !== ""
            width: parent.width
            text: root.hostWidget ? root.hostWidget.microphoneMessage : ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.barForeground
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall * 0.9
          }
        }
        PanelSeparator { width: parent.width; foreground: root.barForeground }
        CaptureButton {
          objectName: "captureButton"
          width: parent.width
          text: "Capture!"
          enabled: root.canStart
          fontFamily: root.panelFontFamily
          foreground: root.barForeground
          hasCursor: root.focusSection === "capture"
          onHovered: function(hovered) { if (hovered) root.setCursor("capture", 0) }
          onClicked: if (root.hostWidget && root.canStart) root.hostWidget.startCapture(root.captureMode)
        }
        Text {
          visible: root.targetType === "monitor" && !root.selectedMonitor
          text: "Pick a monitor first"
          color: root.barForeground
          opacity: 0.6
          font.family: root.panelFontFamily
          font.pixelSize: Style.font.bodySmall * 0.9
        }
      }
    }
  }
}
