import QtQuick
import qs.Commons
import qs.Ui

// Apply state colors directly: hover must not run a fill animation.
BorderSurface {
  id: root
  property string text: ""
  property string iconText: ""
  property string fontFamily: Style.font.family
  readonly property real compactFontSize: Style.font.body * 0.85
  readonly property real paddingX: Style.spacing.controlPaddingX * 0.8
  readonly property real paddingY: Style.spacing.controlPaddingY * 0.65
  property color foreground: Color.foreground
  property color iconColor: selected ? Style.selectedStateColor(foreground, Color.accent) : foreground
  property bool selected: false
  property bool hasCursor: false
  property bool leftAlign: false
  readonly property bool hot: pointer.containsMouse || hasCursor
  readonly property var normalBorder: Border.controlSpec("normal", foreground, Color.accent)
  readonly property var hoverBorder: Border.controlSpec("hover-cursor", foreground, Color.accent)
  readonly property var selectedBorder: Border.controlHasWidth("selected")
    ? Border.controlSpec("selected", foreground, Color.accent) : normalBorder
  readonly property real insetLeft: Math.max(Border.left(normalBorder), Border.left(hoverBorder), Border.left(selectedBorder))
  readonly property real insetRight: Math.max(Border.right(normalBorder), Border.right(hoverBorder), Border.right(selectedBorder))
  readonly property real insetTop: Math.max(Border.top(normalBorder), Border.top(hoverBorder), Border.top(selectedBorder))
  readonly property real insetBottom: Math.max(Border.bottom(normalBorder), Border.bottom(hoverBorder), Border.bottom(selectedBorder))
  signal clicked()
  signal hovered(bool isHovered)

  implicitWidth: caption.implicitWidth + (glyph.visible ? glyph.implicitWidth + label.spacing : 0) + root.paddingX * 2 + insetLeft + insetRight
  implicitHeight: label.implicitHeight + root.paddingY * 2 + insetTop + insetBottom
  opacity: enabled ? 1 : 0.45
  radius: Style.cornerRadius
  borderSpec: hot ? hoverBorder : selected ? selectedBorder : normalBorder
  color: pointer.pressed ? Style.pressedFillFor(foreground, Color.accent)
    : hot ? Style.hoverFillFor(foreground, Color.accent)
    : selected ? Style.selectedFillFor(foreground, Color.accent) : Color.background

  Row {
    id: label
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.insetLeft + root.paddingX
    spacing: Style.spacing.controlGap * 0.8
    Text {
      id: glyph
      visible: root.iconText !== ""
      textFormat: Text.PlainText
      text: root.iconText
      font.family: root.fontFamily
      font.pixelSize: root.compactFontSize
      color: root.iconColor
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: caption
      width: Math.min(implicitWidth, Math.max(0, root.width - root.insetLeft - root.insetRight - root.paddingX * 2 - (glyph.visible ? glyph.width + label.spacing : 0)))
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: root.text
      font.family: root.fontFamily
      font.pixelSize: root.compactFontSize
      font.bold: root.selected
      color: root.selected ? Style.selectedStateColor(root.foreground, Color.accent) : root.foreground
      anchors.verticalCenter: parent.verticalCenter
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: root.clicked()
  }
}
