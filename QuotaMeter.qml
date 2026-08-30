import QtQuick
import qs.Commons
import qs.Ui

// One quota bucket: a labelled meter, or a badge when the bucket is
// unlimited. Both shapes come back from Copilot in the same field, and a
// full-width bar at 0% would read as "none left" rather than "no limit".
Column {
  id: root

  property var bucket: null
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property color track: Style.selectedFillFor(foreground, Color.accent)
  property string fontFamily: Style.font.family
  /** Right-aligned note on the header row — a reset countdown, usually. */
  property string note: ""
  property bool alarming: false
  /** Extra line under the meter. Hidden when empty. */
  property string detail: ""

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property bool unlimited: !!bucket && bucket.unlimited === true
  readonly property real percent: bucket ? Number(bucket.percentUsed || 0) : 0

  visible: !!bucket
  spacing: Style.space(4)

  Row {
    width: parent.width

    PanelSectionHeader {
      id: header
      text: root.bucket ? String(root.bucket.label).toUpperCase() : ""
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Item {
      width: Math.max(0, parent.width - header.implicitWidth - noteText.implicitWidth)
      height: 1
    }

    Text {
      id: noteText
      anchors.verticalCenter: header.verticalCenter
      text: root.unlimited ? "unlimited" : root.note
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    visible: !root.unlimited
    width: parent.width
    height: Style.space(6)
    radius: height / 2
    color: root.track

    Rectangle {
      width: parent.width * root.percent
      height: parent.height
      radius: parent.radius
      color: root.alarming ? root.urgent : root.foreground
      Behavior on width { NumberAnimation { duration: 200 } }
    }
  }

  Text {
    visible: root.detail !== ""
    width: parent.width
    text: root.detail
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
