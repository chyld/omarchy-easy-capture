import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "chyld.easy-capture"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property string captureMode: service ? service.captureMode : "screenshot"
  readonly property string targetType: service ? service.targetType : "region"
  readonly property var monitorList: service ? service.monitors : []
  readonly property string selectedMonitor: service ? service.selectedMonitor : ""
  readonly property var microphoneInputs: service ? service.microphoneInputs : []
  readonly property bool showMicrophones: captureMode === "record" && service && service.microphoneAudio
  readonly property bool showMicrophonePicker: showMicrophones && microphoneInputs.length > 1
  readonly property var microphoneOptions: [{name: "", label: "System default"}].concat(microphoneInputs)
  readonly property bool canStart: service ? service.canStart && service.phase === "idle" : false
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

  function reveal(item) {
    if (!root.opened || !item) return
    Qt.callLater(function() {
      if (!root.opened || !item) return
      var y = item.mapToItem(content, 0, 0).y
      if (y < scroller.contentY) scroller.contentY = y
      else if (y + item.height > scroller.contentY + scroller.height)
        scroller.contentY = y + item.height - scroller.height
      scroller.contentY = Math.max(0, Math.min(scroller.contentY, Math.max(0, content.height - scroller.height)))
    })
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
    if (!service) return
    if (index === 0) service.desktopAudio = !service.desktopAudio
    else service.microphoneAudio = !service.microphoneAudio
  }
  function activateCursor() {
    if (!service) return
    if (focusSection === "mode") service.captureMode = modeValues[selectedIndex]
    else if (focusSection === "target") service.setTargetType(targetValues[selectedIndex])
    else if (focusSection === "monitor" && monitorList[selectedIndex]) service.setSelectedMonitor(monitorList[selectedIndex].name)
    else if (focusSection === "audio") toggleAudio(selectedIndex)
    else if (focusSection === "microphone" && microphoneOptions[selectedIndex]) service.setSelectedMicrophone(microphoneOptions[selectedIndex].name)
    else if (focusSection === "capture" && canStart) service.startCapture(captureMode)
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

      Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: content.implicitHeight
        contentWidth: width
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)
          Text {
            textFormat: Text.PlainText
            text: "Easy Capture"
            color: Color.popups.text
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.body * 0.9
            font.bold: true
          }
          CaptureButtonGroup {
            objectName: "modeTabs"
            width: parent.width
            equalWidth: true
            fontFamily: root.panelFontFamily
            foreground: Color.popups.text
            options: [{value: "screenshot", label: "Screenshot", icon: ""}, {value: "record", label: "Record", icon: ""}]
            value: root.captureMode
            onCursorIndexChanged: if (cursorIndex >= 0) root.reveal(this)
            cursorIndex: root.focusSection === "mode" ? root.selectedIndex : -1
            onHovered: function(index, hovered) { if (hovered) root.setCursor("mode", index) }
            onChanged: function(value) {
              root.setCursor("mode", root.modeValues.indexOf(value))
              if (root.service) root.service.captureMode = value
            }
          }
          Column {
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader { fontSize: Style.font.caption * 0.9; text: "target"; foreground: Color.popups.text }
            CaptureButtonGroup {
              objectName: "targetButtons"
              width: parent.width
              equalWidth: true
              fontFamily: root.panelFontFamily
              foreground: Color.popups.text
              options: [{value: "region", label: "Region", icon: "󰆟"}, {value: "app", label: "App", icon: "󰖯"}, {value: "monitor", label: "Monitor", icon: "󰍹"}]
              value: root.targetType
              onCursorIndexChanged: if (cursorIndex >= 0) root.reveal(this)
              cursorIndex: root.focusSection === "target" ? root.selectedIndex : -1
              onHovered: function(index, hovered) { if (hovered) root.setCursor("target", index) }
              onChanged: function(value) {
                root.setCursor("target", root.targetValues.indexOf(value))
                if (root.service) root.service.setTargetType(value)
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
                  foreground: Color.popups.text
                  iconText: "󰍹"
                  text: modelData.name
                  selected: root.selectedMonitor === modelData.name
                  onHasCursorChanged: if (hasCursor) root.reveal(this)
                  hasCursor: root.focusSection === "monitor" && root.selectedIndex === index
                  onHovered: function(hovered) { if (hovered) root.setCursor("monitor", index) }
                  onClicked: if (root.service) root.service.setSelectedMonitor(modelData.name)
                }
              }
              Text {
                textFormat: Text.PlainText
                visible: root.monitorList.length === 0
                text: "No monitors found"
                color: Color.popups.text
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
            PanelSectionHeader { fontSize: Style.font.caption * 0.9; text: "audio"; foreground: Color.popups.text }
            Repeater {
              model: ["Desktop sounds", "Microphone"]
              delegate: CaptureButton {
                required property string modelData
                required property int index
                readonly property bool checked: root.service ? (index === 0 ? root.service.desktopAudio : root.service.microphoneAudio) : false
                objectName: index === 0 ? "desktopToggle" : "microphoneToggle"
                width: parent.width
                leftAlign: true
                text: modelData + " · " + (checked ? "On" : "Off")
                iconText: index === 0 ? (checked ? "" : "") : (checked ? "󰍬" : "󰍭")
                iconColor: checked ? Style.selectedStateColor(Color.popups.text, Color.accent) : Color.urgent
                selected: checked
                fontFamily: root.panelFontFamily
                foreground: Color.popups.text
                onHasCursorChanged: if (hasCursor) root.reveal(this)
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
              foreground: Color.popups.text
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
                  selected: root.service && root.service.selectedMicrophone === modelData.name
                  fontFamily: root.panelFontFamily
                  foreground: Color.popups.text
                  onHasCursorChanged: if (hasCursor) root.reveal(this)
                  hasCursor: root.focusSection === "microphone" && root.selectedIndex === index
                  onHovered: function(hovered) { if (hovered) root.setCursor("microphone", index) }
                  onClicked: if (root.service) root.service.setSelectedMicrophone(modelData.name)
                }
              }
            }
            Text {
              textFormat: Text.PlainText
              visible: !root.showMicrophonePicker && root.microphoneInputs.length === 1
              width: parent.width
              text: root.microphoneInputs.length ? root.microphoneInputs[0].label : ""
              wrapMode: Text.Wrap
              color: Color.popups.text
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.bodySmall * 0.9
            }
            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.service ? root.service.microphoneMessage : ""
              wrapMode: Text.Wrap
              color: Color.popups.text
              font.family: root.panelFontFamily
              font.pixelSize: Style.font.bodySmall * 0.9
            }
          }
          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: root.service ? root.service.errorMessage : ""
            color: Color.urgent
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall * 0.9
            wrapMode: Text.Wrap
          }
          PanelSeparator { width: parent.width; foreground: Color.popups.text }
          CaptureButton {
            objectName: "captureButton"
            width: parent.width
            text: "Capture!"
            enabled: root.canStart
            fontFamily: root.panelFontFamily
            foreground: Color.popups.text
            onHasCursorChanged: if (hasCursor) root.reveal(this)
            hasCursor: root.focusSection === "capture"
            onHovered: function(hovered) { if (hovered) root.setCursor("capture", 0) }
            onClicked: if (root.service && root.canStart) root.service.startCapture(root.captureMode)
          }
          Text {
            textFormat: Text.PlainText
            visible: root.targetType === "monitor" && !root.selectedMonitor
            text: "Pick a monitor first"
            color: Color.popups.text
            opacity: 0.6
            font.family: root.panelFontFamily
            font.pixelSize: Style.font.bodySmall * 0.9
          }
        }
      }
    }
  }
}
