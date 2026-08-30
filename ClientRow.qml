import QtQuick
import qs.Commons
import qs.Ui

// One client's row: a header that toggles wiring and expands, plus the
// settings that only matter once you care about this client.
//
// Collapsed by default because the common case is "turn it on and forget
// it"; the models are there for the case where the default is wrong. The
// expander is independent of the toggle, so you can inspect a client's
// settings without wiring it, and change models on a wired one without
// unwiring first.
Column {
  id: root

  property string title: ""
  property string subtitle: ""
  property bool wired: false
  property bool expanded: false
  property bool busy: false

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  /** [{ key, label, value, options, onChanged }] rendered as dropdowns. */
  property var fields: []
  /** [{ key, label, description, checked, onChanged }] rendered as switches. */
  property var toggles: []
  /** Shown under the fields when wired — where the config landed. */
  property string wiredNote: ""

  signal toggled()
  signal expandRequested(bool expand)

  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  BorderSurface {
    id: header
    width: parent.width
    implicitHeight: Math.max(Style.space(44), headerRow.implicitHeight + Style.spacing.lg)
    radius: Style.cornerRadius
    color: Style.controlFill(false, headerMouse.containsMouse, root.foreground, root.accent)
    borderSpec: Border.controlSpec(headerMouse.containsMouse ? "hover-cursor" : "normal",
                                   root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 100 } }

    // Covers the label area only. The switch owns its own hit area, so a
    // click meant for the toggle never lands on the expander instead.
    MouseArea {
      id: headerMouse
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: toggle.left
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expandRequested(!root.expanded)
    }

    Row {
      id: headerRow
      anchors.left: parent.left
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.expanded ? "󰅀" : "󰅂"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - parent.children[0].width - Style.space(8))
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: root.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: root.subtitle !== ""
          text: root.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    ToggleSwitch {
      id: toggle
      anchors.right: parent.right
      anchors.rightMargin: Style.spacing.rowPaddingX
      anchors.verticalCenter: parent.verticalCenter
      checked: root.wired
      busy: root.busy
      foreground: root.foreground
      accent: root.accent
      onToggled: root.toggled()
    }
  }

  // Height-animated rather than just visibility-toggled: an expander that
  // snaps makes the whole panel jump, and the rows below it lose their place.
  Item {
    width: parent.width
    clip: true
    height: root.expanded ? body.implicitHeight : 0
    opacity: root.expanded ? 1 : 0

    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Column {
      id: body
      width: parent.width
      spacing: Style.space(8)
      topPadding: Style.space(2)
      bottomPadding: Style.space(4)

      Repeater {
        model: root.fields

        Column {
          required property var modelData
          width: body.width
          spacing: Style.space(3)

          Text {
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.1
          }

          SearchableDropdown {
            width: parent.width
            showLabel: false
            value: modelData.value
            options: modelData.options
            placeholderText: "Search models…"
            emptyText: "No matching model"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onChanged: function(next) {
              if (modelData.onChanged) modelData.onChanged(next)
            }
          }
        }
      }

      Repeater {
        model: root.toggles

        Toggle {
          required property var modelData
          width: body.width
          label: modelData.label
          description: modelData.description || ""
          checked: modelData.checked === true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          onClicked: {
            if (modelData.onChanged) modelData.onChanged(!(modelData.checked === true))
          }
        }
      }

      Text {
        visible: root.wiredNote !== ""
        width: parent.width
        text: root.wiredNote
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
