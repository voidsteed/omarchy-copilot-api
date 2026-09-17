import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon plus panel for the Copilot proxy.
//
// The panel is a ladder: install the service, start it, sign in to GitHub,
// then point a client at it. Each rung only appears once the one below it is
// done, so the panel always shows exactly one obvious next action instead of a
// wall of controls that mostly do not apply yet.
Panel {
  id: root
  moduleName: "voidsteed.copilot-proxy"
  ipcTarget: "copilot-proxy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hideWhenStopped: setting("hideWhenStopped", false) === true

  // Which client's settings are open, or "" for none. One at a time: both
  // expanded at once makes the panel taller than most screens want, and the
  // question the section answers is "which client am I setting up right now".
  property string expandedClient: ""

  // The icon earns attention only when something needs doing: quota nearly
  // spent, or a service that tried to run and failed. A proxy that is simply
  // stopped is a choice, not a problem.
  readonly property bool alarming: model.quotaAlarming || model.failed

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  // A stopped proxy can hide entirely, but never while it is failing — a
  // service that crashed is exactly when you want the icon there to click.
  visible: !hideWhenStopped || model.running || model.activating || model.failed

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    model.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    // Reopening should show the panel's overview, not whatever drawer was
    // left open last time.
    expandedClient = ""
  }

  Model {
    id: model
    settings: root.settings
    // Gives the model a route to shell.json, so a model picked in a dropdown
    // is still picked after a shell restart.
    bar: root.bar
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { model.refresh(); return "ok" }
    function start(): string { model.start(); return "ok" }
    function stop(): string { model.stop(); return "ok" }
    function restart(): string { model.restart(); return "ok" }
    function useClaude(): string { model.useClaude(); return "ok" }
    function useCodex(): string { model.useCodex(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Nerd Font: a running proxy gets the filled cloud, a stopped one the
    // outline, and a failure the slashed cloud.
    text: model.failed ? "󰅤" : (model.running ? "󰅠" : "󰅢")
    active: root.alarming || model.running
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) model.running ? model.stop() : model.start()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          flick.contentY = root.clamp(flick.contentY + dy * Style.space(56), 0,
                                      Math.max(0, flick.contentHeight - flick.height))
      }
      onActivateRequested: model.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") model.refresh()
        else if (t === "s" || t === "S") model.running ? model.stop() : model.start()
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          // ---------------------------------------------- hero: on/off
          PanelHero {
            width: parent.width
            title: "Copilot Proxy"
            meta: model.statusText
            detail: model.running ? (":" + model.port) : ""
            foreground: model.failed ? root.urgent : root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: model.failed ? "󰅤" : (model.running ? "󰅠" : "󰅢")
                color: model.failed ? root.urgent
                  : (model.running ? root.foreground : Qt.darker(root.foreground, 1.8))
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }

            // The switch is the panel's primary verb, so it sits in the hero
            // rather than down among the secondary buttons. Disabled until
            // there is something to start.
            trailingControl: Component {
              ToggleSwitch {
                checked: model.running || model.activating
                enabled: model.proxyInstalled && !model.activating
                foreground: root.foreground
                accent: Color.accent
                onToggled: model.running ? model.stop() : model.start()
              }
            }
          }

          // ---------------------------------------------- setup prompts
          //
          // Exactly one of these shows at a time — the first unmet
          // prerequisite going down the ladder.

          // Nothing to run. This one cannot be fixed from the panel, so it
          // gives the command instead of a button that would only fail.
          Column {
            visible: model.everLoaded && !model.proxyInstalled
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: "copilot-proxy-api is not on PATH."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "npm i -g copilot-proxy-api"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
            }
          }

          Button {
            visible: model.everLoaded && model.proxyInstalled && !model.unitInstalled
            width: parent.width
            text: "Install service"
            tooltipText: "Write ~/.config/systemd/user/" + model.service + ".service"
            iconText: "󰑮"
            bordered: true
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: model.installUnit()
          }

          // ---------------------------------------------- sign in
          //
          // The device-code card. Shows the code, a way to copy it, and a way
          // to open the page — the three things the flow needs — and polls
          // itself out of existence once GitHub approves.
          Column {
            visible: model.reachable && !model.authenticated
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "GITHUB"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Button {
              visible: !model.authPending
              width: parent.width
              text: "Sign in to GitHub"
              iconText: "󰊤"
              bordered: true
              focusable: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: model.signIn()
            }

            // The code, large and monospaced, because it gets typed by hand
            // into a browser on a device that may not be this one.
            BorderSurface {
              visible: model.authPending
              width: parent.width
              implicitHeight: codeColumn.implicitHeight + Style.space(16)
              color: Style.normalFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              Column {
                id: codeColumn
                anchors.centerIn: parent
                width: parent.width - Style.space(16)
                spacing: Style.space(8)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: model.userCode
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  font.letterSpacing: 3
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(8)

                  Button {
                    text: "Copy"
                    iconText: "󰆏"
                    bordered: true
                    focusable: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: model.copyCode()
                  }

                  Button {
                    text: "Open GitHub"
                    iconText: "󰖟"
                    bordered: true
                    focusable: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    onClicked: model.openVerificationPage()
                  }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Waiting for approval…"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          // ---------------------------------------------- quota meter
          // ---------------------------------------------- usage
          //
          // Two different questions, in order: what GitHub has metered
          // (the quota, shared across every Copilot client you use), and
          // what this proxy actually served (the week, local to here).
          Column {
            visible: model.quotaBuckets.length > 0 || model.hasHistory
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Repeater {
              model: model.quotaBuckets

              QuotaMeter {
                required property var modelData
                required property int index

                width: parent.width
                bucket: modelData
                foreground: root.foreground
                urgent: root.urgent
                track: root.track
                fontFamily: root.fontFamily
                // The reset date covers every bucket, so it is stated once,
                // on the first one, instead of repeated down the column.
                note: index === 0 ? model.formatResetCountdown() : ""
                alarming: modelData.id === "premium_interactions" && model.quotaAlarming
                detail: {
                  if (modelData.unlimited) return ""
                  var text = model.formatCount(modelData.used)
                    + " of " + model.formatCount(modelData.entitlement)
                    + (modelData.tokenBased ? " credits" : " used")
                    + " · " + Math.round(modelData.percentUsed * 100) + "%"
                  if (index === 0 && model.plan !== "") text += " · " + model.plan
                  return text
                }
              }
            }

            // Local history. Hidden until there is something to show: an
            // empty chart on a fresh install is noise, not information.
            Column {
              visible: model.hasHistory
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width

                PanelSectionHeader {
                  id: weekHeader
                  text: "LAST 7 DAYS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Item {
                  width: Math.max(0, parent.width - weekHeader.implicitWidth - weekTotal.implicitWidth)
                  height: 1
                }

                Text {
                  id: weekTotal
                  anchors.verticalCenter: weekHeader.verticalCenter
                  text: model.formatCount(model.weekRequests)
                    + (model.weekRequests === 1 ? " request" : " requests")
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Sparkline {
                width: parent.width
                days: model.recentDays
                peak: model.weekPeak
                foreground: root.foreground
                track: root.track
                fontFamily: root.fontFamily
                tooltipFor: function(day) { return model.dayTooltip(day) }
              }
            }
          }

          // ---------------------------------------------- client config
          Column {
            visible: model.everLoaded && model.proxyInstalled
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              text: "USE WITH"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // Independent toggles rather than a radio group: the two clients
            // read different config files and can both point here at once,
            // so forcing a single choice would misrepresent what is possible.
            ClientRow {
              width: parent.width
              title: "Claude Code"
              subtitle: model.claudeWired
                ? (model.claudeClient && model.claudeClient.model
                   ? String(model.claudeClient.model) : "wired")
                : "~/.claude/settings.json"
              wired: model.claudeWired
              expanded: root.expandedClient === "claude"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              wiredNote: model.claudeWired
                ? "Wired to " + model.baseUrl + " · restart Claude Code to pick it up"
                : ""
              onToggled: model.claudeWired ? model.unsetClaude() : model.useClaude()
              onExpandRequested: function(expand) {
                root.expandedClient = expand ? "claude" : ""
              }
              fields: [
                {
                  key: "claudeModel",
                  label: "MODEL",
                  value: model.claudeModel,
                  options: model.claudeModelOptions,
                  onChanged: function(id) { model.setClaudeModel(id) }
                },
                {
                  key: "claudeSmallModel",
                  label: "SMALL / FAST MODEL",
                  value: model.claudeSmallModel,
                  options: model.claudeSmallModelOptions,
                  onChanged: function(id) { model.setClaudeSmallModel(id) }
                },
                {
                  key: "claudeEffort",
                  label: "EFFORT",
                  value: model.claudeEffort,
                  options: model.claudeEffortOptions,
                  onChanged: function(level) { model.setClaudeEffort(level) }
                }
              ]
              toggles: [
                {
                  key: "claudeUltracode",
                  label: "Ultracode",
                  description: "Orchestrate every task with multi-agent workflows",
                  checked: model.claudeUltracode,
                  onChanged: function(on) { model.setClaudeUltracode(on) }
                }
              ]
            }

            ClientRow {
              width: parent.width
              title: "Codex CLI"
              subtitle: model.codexWired
                ? (model.codexClient && model.codexClient.model
                   ? String(model.codexClient.model) : "wired")
                : "~/.codex/config.toml"
              wired: model.codexWired
              expanded: root.expandedClient === "codex"
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              wiredNote: model.codexWired
                ? "Wired to " + model.baseUrl + "/v1 · restart Codex to pick it up"
                : ""
              onToggled: model.codexWired ? model.unsetCodex() : model.useCodex()
              onExpandRequested: function(expand) {
                root.expandedClient = expand ? "codex" : ""
              }
              fields: [
                {
                  key: "codexModel",
                  label: "MODEL",
                  value: model.codexModel,
                  options: model.codexModelOptions,
                  onChanged: function(id) { model.setCodexModel(id) }
                },
                {
                  key: "codexReasoningEffort",
                  label: "REASONING EFFORT",
                  value: model.codexReasoningEffort,
                  options: model.codexEffortOptions,
                  onChanged: function(level) { model.setCodexReasoningEffort(level) }
                }
              ]
            }
          }

          // ---------------------------------------------- footer actions
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSeparator { width: parent.width; foreground: root.foreground }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                text: "Restart"
                iconText: "󰑓"
                bordered: true
                focusable: true
                enabled: model.unitInstalled
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: model.restart()
              }

              Button {
                text: "Logs"
                iconText: "󰗚"
                bordered: true
                focusable: true
                enabled: model.unitInstalled && model.serviceNameValid
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: {
                  // The service name is interpolated into a command string
                  // that reaches a shell, so it is checked rather than
                  // quoted: a valid systemd unit name contains no shell
                  // metacharacters, and an invalid one has nothing to show.
                  if (root.bar && model.serviceNameValid) {
                    root.bar.run("omarchy-launch-tui journalctl --user -u " + model.service + " -f -n 100")
                  }
                  root.close()
                }
              }

              Button {
                text: "Usage"
                iconText: "󰄨"
                bordered: true
                focusable: true
                enabled: model.reachable
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: { model.dashboard(); root.close() }
              }
            }

            Text {
              visible: model.lastError !== ""
              width: parent.width
              text: model.lastError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 3
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
