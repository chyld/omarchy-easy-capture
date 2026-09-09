import QtQuick
import qs.Commons

Row {
  id: root
  property var options: []
  property string value: ""
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  property bool equalWidth: false
  property int cursorIndex: -1
  signal changed(string value)
  signal hovered(int index, bool isHovered)
  spacing: Style.spacing.md * 0.75

  Repeater {
    model: root.options
    delegate: CaptureButton {
      required property var modelData
      required property int index
      width: root.equalWidth ? (root.width - root.spacing * (root.options.length - 1)) / root.options.length : implicitWidth
      text: modelData.label
      iconText: modelData.icon || ""
      fontFamily: root.fontFamily
      foreground: root.foreground
      selected: root.value === modelData.value
      hasCursor: root.cursorIndex === index
      onClicked: root.changed(modelData.value)
      onHovered: function(h) { root.hovered(index, h) }
    }
  }
}
