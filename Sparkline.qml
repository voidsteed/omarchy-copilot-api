import QtQuick
import qs.Commons
import qs.Ui

// Seven days of request volume as a row of bars.
//
// Deliberately not a line chart: with seven points and a frequently-zero
// series, bars say "nothing happened Tuesday" more clearly than a line
// dipping to the axis. Each bar carries a tooltip with the exact count,
// because the chart's job is the shape and the tooltip's is the number.
Column {
  id: root

  /** [{ date: "YYYY-MM-DD", requests: n }], oldest first. */
  property var days: []
  property int peak: 0
  property color foreground: Color.foreground
  property color track: Style.selectedFillFor(foreground, Color.accent)
  property string fontFamily: Style.font.family
  property real barHeight: Style.space(34)
  /** Called with a day entry; should return tooltip text. */
  property var tooltipFor: null

  readonly property color dim: Qt.darker(foreground, 1.55)
  // A flat series should not render as seven full-height bars, so the scale
  // floors at 1 and an all-zero week draws nothing rather than everything.
  readonly property real scale: Math.max(1, peak)

  spacing: Style.space(4)

  Row {
    width: parent.width
    height: root.barHeight
    spacing: Style.space(3)

    Repeater {
      model: root.days

      Item {
        id: column
        required property var modelData
        required property int index

        readonly property real count: Number(modelData.requests || 0)
        // Today is the rightmost bar and the only partial one, so it is drawn
        // in outline to avoid reading as a completed day that came up short.
        readonly property bool isToday: index === root.days.length - 1

        width: Math.max(1, (parent.width - (root.days.length - 1) * Style.space(3)) / root.days.length)
        height: parent.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height
          radius: Style.cornerRadius > 0 ? Style.space(2) : 0
          color: root.track
        }

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          // Any nonzero day gets a visible sliver: a day with one request
          // rounding to zero pixels is indistinguishable from an idle one.
          height: column.count > 0
            ? Math.max(Style.space(2), parent.height * (column.count / root.scale))
            : 0
          radius: Style.cornerRadius > 0 ? Style.space(2) : 0
          color: root.foreground
          opacity: column.isToday ? 0.55 : 1.0
          Behavior on height { NumberAnimation { duration: 180 } }
        }

        MouseArea {
          id: hover
          anchors.fill: parent
          hoverEnabled: true
        }

        PanelToolTip {
          visible: hover.containsMouse && root.tooltipFor !== null
          text: root.tooltipFor ? root.tooltipFor(column.modelData) : ""
          fontFamily: root.fontFamily
        }
      }
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(3)

    Repeater {
      model: root.days

      Text {
        required property var modelData
        width: Math.max(1, (root.width - (root.days.length - 1) * Style.space(3)) / root.days.length)
        horizontalAlignment: Text.AlignHCenter
        text: {
          var parsed = new Date(String(modelData.date || "") + "T00:00:00")
          return isNaN(parsed.getTime()) ? "" : ["S", "M", "T", "W", "T", "F", "S"][parsed.getDay()]
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
