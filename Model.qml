import QtQuick
import Quickshell
import Quickshell.Io

// State layer for the Copilot Proxy panel.
//
// Every fact the panel draws arrives through `omarchy-copilot-proxy status`,
// which folds systemd state, the proxy's own /status endpoint, Copilot quota,
// and the current Claude/Codex wiring into one JSON document. Keeping the
// shelling-out here means the panel is a pure function of `snapshot`, and the
// side-effecting commands all funnel through one place that knows how to
// serialize them.
Item {
  id: root
  visible: false

  property var settings: ({})

  // The bar hands the widget its shell.json entry, and writing back through
  // the shell is what makes a choice made in the panel outlive the session.
  // Null when the widget is hosted somewhere that cannot persist, in which
  // case selections still apply — they just do not stick.
  property QtObject bar: null

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property bool canPersist: !!bar && !!bar.shell
    && typeof bar.shell.mutateShellConfig === "function"

  /**
   * Persist one setting into this widget's entry in shell.json.
   *
   * The entry is found by plugin id across every bar region, because a user
   * who moved the widget to another section should not lose the ability to
   * configure it. `settings` is updated locally too: the bar pushes the new
   * value back down eventually, but the UI should not wait for a file write
   * to show what was just clicked.
   */
  function persistSetting(name, value) {
    var next = {}
    for (var key in settings) next[key] = settings[key]
    next[name] = value
    settings = next

    if (!canPersist) return
    bar.shell.mutateShellConfig(function(config) {
      if (!config.bar || !config.bar.layout) return
      var regions = ["left", "center", "right"]
      for (var r = 0; r < regions.length; r++) {
        var entries = config.bar.layout[regions[r]]
        if (!Array.isArray(entries)) continue
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          if (!entry || entry.id !== root.moduleId) continue
          entry[name] = value
          return
        }
      }
    })
  }

  readonly property string moduleId: "voidsteed.copilot-proxy"

  readonly property int port: Number(setting("port", 4141))
  readonly property string service: String(setting("service", "copilot-proxy-api"))

  // Whether the configured unit name is one systemd would accept. Mirrors
  // valid_service_name() in the helper. The panel builds a shell command
  // string around this value for the Logs button, so a name outside the
  // charset is a reason to disable that button rather than to interpolate
  // and hope — systemd's charset has no shell metacharacters in it, which is
  // what makes checking the name sufficient there.
  readonly property bool serviceNameValid: /^[A-Za-z0-9][A-Za-z0-9_.@-]{0,63}$/.test(service)
  readonly property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 300)))
  readonly property string claudeModel: String(setting("claudeModel", "claude-opus-5"))
  readonly property string claudeSmallModel: String(setting("claudeSmallModel", "claude-sonnet-5"))
  readonly property string claudeEffort: String(setting("claudeEffort", "default"))
  readonly property bool claudeUltracode: setting("claudeUltracode", false) === true
  readonly property string codexModel: String(setting("codexModel", "gpt-5.5"))
  readonly property string codexReasoningEffort: String(setting("codexReasoningEffort", "high"))

  // The helper lives next to this file, so a plugin installed anywhere is
  // still able to find its own binary without touching PATH.
  readonly property string helper: {
    var url = String(Qt.resolvedUrl("bin/omarchy-copilot-proxy"))
    return url.indexOf("file://") === 0 ? url.slice(7) : url
  }

  // ------------------------------------------------------------- snapshot

  property var snapshot: null
  property bool everLoaded: false
  property string lastError: ""

  readonly property bool unitInstalled: snapshot ? snapshot.unitInstalled === true : false
  readonly property string activeState: snapshot ? String(snapshot.active || "unknown") : "unknown"
  readonly property bool running: activeState === "active"
  readonly property bool activating: activeState === "activating"
  readonly property bool failed: activeState === "failed"
  readonly property bool reachable: snapshot ? snapshot.reachable === true : false
  readonly property string baseUrl: snapshot ? String(snapshot.baseUrl || "") : "http://localhost:" + port
  readonly property bool proxyInstalled: snapshot ? String(snapshot.proxyCommand || "") !== "" : false

  readonly property var proxyStatus: snapshot ? snapshot.proxy : null
  readonly property bool authenticated: proxyStatus ? proxyStatus.authenticated === true : false
  readonly property bool ready: proxyStatus ? proxyStatus.ready === true : false
  readonly property string githubUser: proxyStatus && proxyStatus.user ? String(proxyStatus.user) : ""
  readonly property var models: proxyStatus && proxyStatus.models ? proxyStatus.models : []

  readonly property var authSession: proxyStatus && proxyStatus.auth ? proxyStatus.auth : null
  readonly property string authStatus: authSession ? String(authSession.status || "idle") : "idle"
  readonly property string userCode: authSession ? sanitizedUserCode(authSession.userCode) : ""

  // Where the sign-in button sends the browser. The proxy supplies this, and
  // the proxy is a separate program listening on a port — so the value is
  // treated as untrusted input rather than as a fact. Only GitHub's own
  // device-login page is ever opened; anything else falls back to the
  // canonical URL instead of being honoured.
  readonly property string deviceLoginUrl: "https://github.com/login/device"
  readonly property string verificationUri: {
    var advertised = authSession ? String(authSession.verificationUri || "") : ""
    return isDeviceLoginUrl(advertised) ? advertised : deviceLoginUrl
  }
  readonly property bool authPending: authStatus === "pending"

  /**
   * Whether a URL is GitHub's device-login page and nothing else.
   *
   * Fails closed: the whole string has to be the expected URL, so a `file://`
   * path, a `javascript:` payload, a lookalike host, or a redirector with the
   * real URL in its query string are all rejected. Matching the parsed
   * authority rather than a prefix is deliberate — `https://github.com.evil.tld`
   * and `https://evil.tld/?x=https://github.com/login/device` both pass a
   * `startsWith` check, as does `https://github.com@evil.tld/...`, where the
   * real host sits after credentials.
   *
   * Anchored at both ends, so there is no query string or fragment to carry a
   * payload and no trailing-slash variant to normalize away. GitHub's device
   * page needs neither: the code is typed in, not passed in the URL.
   */
  function isDeviceLoginUrl(url) {
    return String(url || "").toLowerCase() === deviceLoginUrl
  }

  // The code is drawn into the panel and copied to the clipboard, so it is
  // held to the shape GitHub actually issues (`ABCD-1234`). Checked as it
  // arrived rather than trimmed first: whitespace around it means the value
  // is not what it claims to be, and quietly cleaning it up would hide that
  // while still putting the result on the clipboard.
  function sanitizedUserCode(code) {
    var text = String(code || "")
    return /^[A-Za-z0-9-]{1,32}$/.test(text) ? text : ""
  }

  readonly property var claudeClient: snapshot && snapshot.clients ? snapshot.clients.claude : null
  readonly property var codexClient: snapshot && snapshot.clients ? snapshot.clients.codex : null
  readonly property bool claudeWired: claudeClient ? claudeClient.wired === true : false
  readonly property bool codexWired: codexClient ? codexClient.wired === true : false

  // Which client is "the" mode. Both wired at once is legal — they read
  // different files — so the mode is only unambiguous when exactly one is.
  readonly property string mode: {
    if (claudeWired && codexWired) return "both"
    if (claudeWired) return "claude"
    if (codexWired) return "codex"
    return "none"
  }

  // ---------------------------------------------------------------- quota

  // Copilot reports several quota buckets. They share a shape, so they are
  // normalized into one record each and the panel renders whichever exist —
  // a plan that gains or loses a bucket needs no change here.
  function quotaBucket(id, label, snapshot, usage) {
    if (!snapshot) return null
    var entitlement = Number(snapshot.entitlement || 0)
    var remaining = Number(snapshot.remaining || 0)
    var unlimited = snapshot.unlimited === true
    // An unlimited bucket reports zero entitlement, which is not the same as
    // a metered bucket that has run out. Percent is meaningless for it.
    var used = unlimited || !(entitlement > 0) ? 0 : entitlement - remaining
    return {
      id: id,
      label: label,
      unlimited: unlimited,
      entitlement: entitlement,
      remaining: remaining,
      used: used,
      percentUsed: entitlement > 0 ? Math.max(0, Math.min(1, used / entitlement)) : 0,
      creditsUsed: Number(snapshot.credits_used || 0),
      tokenBased: snapshot.token_based_billing === true,
      overagePermitted: snapshot.overage_permitted === true,
      overageCount: Number(snapshot.overage_count || 0)
    }
  }

  readonly property var quotaBuckets: {
    var usage = root.usageRecord
    if (!usage || !usage.quota_snapshots) return []
    var snapshots = usage.quota_snapshots
    var out = []
    // Premium first: it is the one that actually runs out, so it leads.
    var order = [
      { id: "premium_interactions", label: "Premium requests" },
      { id: "chat", label: "Chat" },
      { id: "completions", label: "Completions" }
    ]
    for (var i = 0; i < order.length; i++) {
      var bucket = quotaBucket(order[i].id, order[i].label, snapshots[order[i].id], usage)
      if (bucket) out.push(bucket)
    }
    return out
  }

  // The bucket the meters and the alarm speak for.
  readonly property var quota: {
    var buckets = root.quotaBuckets
    for (var i = 0; i < buckets.length; i++)
      if (buckets[i].id === "premium_interactions") return buckets[i]
    return buckets.length > 0 ? buckets[0] : null
  }

  readonly property string plan: {
    var usage = root.usageRecord
    return usage ? String(usage.copilot_plan || "") : ""
  }

  readonly property string resetDate: {
    var usage = root.usageRecord
    return usage ? String(usage.quota_reset_date || "") : ""
  }

  // Milliseconds until the quota window rolls over. The API gives a date, not
  // a time, so this is midnight local on that date — close enough for "3d".
  readonly property double resetMs: {
    var tick = root.nowMs
    if (root.resetDate === "") return -1
    var parsed = new Date(root.resetDate + "T00:00:00")
    if (isNaN(parsed.getTime())) return -1
    return parsed.getTime() - tick
  }

  // Recomputed on a timer so a panel left open keeps telling the truth.
  property double nowMs: Date.now()

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  readonly property bool quotaAlarming: !!quota && !quota.unlimited
    && quota.entitlement > 0 && quota.percentUsed >= 0.9

  property var usageRecord: null

  // -------------------------------------------------------------- history

  // What this proxy served, per local day, oldest first. Distinct from the
  // quota above: that is what GitHub metered across every client, this is
  // what came through here.
  readonly property var recentDays: {
    var status = root.proxyStatus
    if (!status || !status.history || !status.history.recentDays) return []
    return status.history.recentDays
  }

  readonly property int historyTotal: {
    var status = root.proxyStatus
    return status && status.history ? Number(status.history.total || 0) : 0
  }

  readonly property int weekRequests: {
    var days = root.recentDays
    var total = 0
    for (var i = 0; i < days.length; i++) total += Number(days[i].requests || 0)
    return total
  }

  readonly property int weekPeak: {
    var days = root.recentDays
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].requests || 0))
    return peak
  }

  readonly property bool hasHistory: weekRequests > 0

  // ------------------------------------------------------------- polling

  Process {
    id: statusProcess
    running: false
    command: [root.helper, "status", "--port", String(root.port), "--service", root.service]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.lastError = text.trim()
    }
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function applyStatus(output) {
    var text = String(output || "").trim()
    if (text === "") return
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") {
        root.snapshot = parsed
        root.everLoaded = true
        root.lastError = ""
        // Quota is only fetchable once the proxy is up and signed in; asking
        // otherwise just logs a connection refusal every poll.
        if (root.reachable && root.authenticated) root.refreshUsage()
        else root.usageRecord = null
      }
    } catch (e) {
      console.warn("copilot-proxy", "Ignoring bad status payload", e)
    }
  }

  Process {
    id: usageProcess
    running: false
    command: ["curl", "-fsS", "--max-time", "4", root.baseUrl + "/usage"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyUsage(text)
    }
    // A quota fetch that fails is not worth a visible error: the panel simply
    // shows no meter, and the next poll tries again.
    stderr: StdioCollector { waitForEnd: true }
  }

  function refreshUsage() {
    if (!usageProcess.running) usageProcess.running = true
  }

  function applyUsage(output) {
    var text = String(output || "").trim()
    if (text === "") { root.usageRecord = null; return }
    try {
      var parsed = JSON.parse(text)
      root.usageRecord = (parsed && typeof parsed === "object" && !parsed.error) ? parsed : null
    } catch (e) {
      root.usageRecord = null
    }
  }

  // Poll fast while a login is in flight or the service is mid-transition —
  // both resolve in seconds and the panel should not sit on a stale answer —
  // and fall back to the configured interval once things settle.
  readonly property int pollIntervalMs: {
    if (root.authPending) return 2000
    if (root.activating) return 2000
    return root.refreshIntervalSec * 1000
  }

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // --------------------------------------------------------- model lists

  // Dropdown options for a client. Copilot advertises embedding models and
  // internal entries that no coding agent can use as its main model, so the
  // list is filtered per client rather than shown raw.
  //
  // A model currently selected but missing from the live list is kept and
  // marked, because silently dropping it would make the dropdown disagree
  // with the config file it is supposed to be showing.
  function modelOptions(kind, selected) {
    var available = root.models || []
    var options = []
    var seen = {}

    for (var i = 0; i < available.length; i++) {
      var id = String(available[i])
      if (!modelSuitable(kind, id)) continue
      seen[id] = true
      options.push({ value: id, label: id, description: modelFamily(id) })
    }

    var current = String(selected || "")
    // The kept-but-missing entry still has to be well-formed. It comes from
    // the persisted setting rather than the live list, which is the one path
    // into this list that does not already pass modelSuitable().
    if (current !== "" && !seen[current] && validModelId(current)) {
      options.unshift({
        value: current,
        label: current,
        description: available.length > 0 ? "not offered by your plan" : "current"
      })
    }
    return options
  }

  // Claude Code needs an Anthropic-shaped model; Codex drives the Responses
  // API, which the GPT-5 line and everything after it implements. Copilot
  // advertises gpt-4o and gpt-3.5-turbo too, but offering them here would be a
  // list of ways to get a confusing failure rather than a list of choices.
  //
  // The cutoff is a major-version floor, not a `gpt-5` prefix: pinning the
  // literal string meant every model past that line — gpt-6 and later — was
  // silently missing from the dropdown the day it shipped, including one a
  // user could already be running.
  function modelSuitable(kind, id) {
    // First gate is shape, not suitability: this list arrives from the proxy
    // and a chosen entry is passed through to the helper, which writes it into
    // ~/.codex/config.toml. The helper enforces the same grammar and refuses
    // anything outside it — filtering here too means a malformed id never
    // reaches the dropdown to be chosen in the first place, rather than being
    // offered and then failing at write time.
    if (!validModelId(id)) return false
    if (id.indexOf("embedding") >= 0) return false
    if (id.indexOf("trajectory-") === 0) return false
    if (kind === "claude") return id.indexOf("claude-") === 0
    if (kind === "codex") return gptMajorVersion(id) >= 5
    return true
  }

  // Major version of a `gpt-<n>` id, or 0 for anything that is not one.
  // Matches `gpt-5`, `gpt-5.5`, `gpt-6-astra`, `gpt-10` — and orders them
  // numerically, so a two-digit major is not mistaken for a smaller one.
  //
  // Azure spells the old GPT-3.5 as `gpt-35-turbo`, where `35` is one number
  // meaning 3.5 rather than a major of thirty-five. That is a closed set of
  // legacy names, so they are listed rather than inferred from shape — a rule
  // like "two digits starting 1-4" would also swallow a real future gpt-10.
  readonly property var dotlessLegacyMajors: ({ "35": true, "45": true })

  function gptMajorVersion(id) {
    var match = /^gpt-(\d+)(?=$|[.-])/.exec(String(id || ""))
    if (!match) return 0
    if (dotlessLegacyMajors[match[1]] === true) return 0
    return Number(match[1])
  }

  // Mirror of valid_model_id() in bin/omarchy-copilot-proxy. Single line, no
  // quotes and no backslashes, so the value cannot terminate the TOML string
  // it is written into or open a key of its own after it.
  function validModelId(id) {
    return /^[A-Za-z0-9][A-Za-z0-9._:\/-]{0,127}$/.test(String(id || ""))
  }

  function modelFamily(id) {
    if (id.indexOf("claude-opus") === 0) return "Anthropic · heavy"
    if (id.indexOf("claude-sonnet") === 0) return "Anthropic · balanced"
    if (id.indexOf("claude-haiku") === 0) return "Anthropic · fast"
    if (id.indexOf("claude-") === 0) return "Anthropic"
    if (id.indexOf("gpt-5") === 0) return "OpenAI · current"
    if (id.indexOf("gpt-") === 0) return "OpenAI"
    if (id.indexOf("gemini-") === 0) return "Google"
    if (id.indexOf("grok-") === 0) return "xAI"
    return ""
  }

  readonly property var claudeModelOptions: modelOptions("claude", root.claudeModel)
  readonly property var claudeSmallModelOptions: modelOptions("claude", root.claudeSmallModel)
  readonly property var codexModelOptions: modelOptions("codex", root.codexModel)

  readonly property var codexEffortOptions: [
    { value: "minimal", label: "minimal", description: "least deliberate" },
    { value: "low", label: "low", description: "fast" },
    { value: "medium", label: "medium", description: "balanced" },
    { value: "high", label: "high", description: "recommended" },
    { value: "xhigh", label: "xhigh", description: "more thorough" },
    { value: "max", label: "max", description: "very thorough" },
    { value: "ultra", label: "ultra", description: "slowest, most thorough" }
  ]

  // Claude Code's own --effort levels. "default" is not one of them: it means
  // leave the setting out entirely and let Claude Code decide, which is a
  // different state from pinning a level and the one a fresh install has.
  readonly property var claudeEffortOptions: [
    { value: "default", label: "default", description: "let Claude Code choose" },
    { value: "low", label: "low", description: "fast" },
    { value: "medium", label: "medium", description: "balanced" },
    { value: "high", label: "high", description: "thorough" },
    { value: "xhigh", label: "xhigh", description: "more thorough" },
    { value: "max", label: "max", description: "slowest, most thorough" }
  ]

  // Changing a model only means something once it is written to the client's
  // config, so a change to an already-wired client rewires it immediately.
  // Changing one that is off just records the choice for when it is turned on.
  //
  // Each setter validates before persisting: a rejected value is never stored,
  // so a bad id cannot be written once and then replayed out of settings.json
  // on every later start.
  function setClaudeModel(id) {
    if (id === root.claudeModel || !validModelId(id)) return
    persistSetting("claudeModel", id)
    if (root.claudeWired) useClaude()
  }

  function setClaudeSmallModel(id) {
    if (id === root.claudeSmallModel || !validModelId(id)) return
    persistSetting("claudeSmallModel", id)
    if (root.claudeWired) useClaude()
  }

  function setClaudeEffort(level) {
    if (level === root.claudeEffort || !isOption(root.claudeEffortOptions, level)) return
    persistSetting("claudeEffort", level)
    if (root.claudeWired) useClaude()
  }

  function setClaudeUltracode(enabled) {
    if (enabled === root.claudeUltracode) return
    persistSetting("claudeUltracode", enabled === true)
    if (root.claudeWired) useClaude()
  }

  function setCodexModel(id) {
    if (id === root.codexModel || !validModelId(id)) return
    persistSetting("codexModel", id)
    if (root.codexWired) useCodex()
  }

  function setCodexReasoningEffort(level) {
    if (level === root.codexReasoningEffort || !isOption(root.codexEffortOptions, level)) return
    persistSetting("codexReasoningEffort", level)
    if (root.codexWired) useCodex()
  }

  // Effort levels are a closed set the helper also enforces, so membership in
  // the list the panel offers is the whole check.
  function isOption(options, value) {
    for (var i = 0; i < options.length; i++) {
      if (options[i].value === value) return true
    }
    return false
  }

  // ------------------------------------------------------------- actions

  // Actions are fire-and-forget: each one changes state the next status poll
  // will observe, so the panel never needs their output. Serializing them
  // through one process keeps a double-click from racing two systemctl calls.
  Process {
    id: actionProcess
    running: false
    onExited: {
      if (root.pendingAction.length > 0) {
        var next = root.pendingAction
        root.pendingAction = []
        root.runAction(next)
      } else {
        // Deliberately after the action completes, not alongside it: the
        // point is to observe the world the action just made.
        root.refresh()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") {
        root.lastError = text.trim()
        console.warn("copilot-proxy", text.trim())
      }
    }
  }

  property var pendingAction: []

  function runAction(argv) {
    if (actionProcess.running) {
      root.pendingAction = argv
      return
    }
    root.lastError = ""
    actionProcess.command = argv
    actionProcess.running = true
  }

  function helperArgs(action) {
    return [root.helper, action, "--port", String(root.port), "--service", root.service]
  }

  function start() { runAction(helperArgs("start")) }
  function stop() { runAction(helperArgs("stop")) }
  function restart() { runAction(helperArgs("restart")) }
  function installUnit() { runAction(helperArgs("install-unit")) }
  function dashboard() { runAction(helperArgs("dashboard")) }

  // Wiring a client sends the stored model ids to the helper, which writes
  // them into a config file. The setters already validate, but a settings.json
  // edited by hand reaches these functions without passing one — so the values
  // are checked here too, where they actually leave QML. The helper rejects
  // them a second time; none of the three layers is load-bearing alone.
  function useClaude() {
    if (!validModelId(root.claudeModel) || !validModelId(root.claudeSmallModel)) {
      root.lastError = "Refusing to apply an invalid model id"
      return
    }
    var argv = helperArgs("use-claude")
      .concat(["--model", root.claudeModel, "--small-model", root.claudeSmallModel])
    // "default" means omit the key, so it is expressed by not passing a flag
    // rather than by writing the word "default" into settings.json.
    if (root.claudeEffort !== "default" && isOption(root.claudeEffortOptions, root.claudeEffort)) {
      argv = argv.concat(["--effort", root.claudeEffort])
    }
    if (root.claudeUltracode) argv = argv.concat(["--ultracode"])
    runAction(argv)
  }

  function useCodex() {
    if (!validModelId(root.codexModel)) {
      root.lastError = "Refusing to apply an invalid model id"
      return
    }
    var effort = isOption(root.codexEffortOptions, root.codexReasoningEffort)
      ? root.codexReasoningEffort : "high"
    runAction(helperArgs("use-codex")
      .concat(["--model", root.codexModel, "--reasoning-effort", effort]))
  }

  function unsetClaude() { runAction(helperArgs("unset-claude")) }
  function unsetCodex() { runAction(helperArgs("unset-codex")) }

  // Sign-in is the one action that talks to the proxy rather than the helper:
  // it needs the server already running to host the device-flow session.
  Process {
    id: authProcess
    running: false
    command: ["curl", "-fsS", "--max-time", "10", "-X", "POST", root.baseUrl + "/status/auth/start"]
    onExited: root.refresh()
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") root.lastError = "Sign-in failed. Is the proxy running?"
    }
  }

  function signIn() {
    if (!authProcess.running) authProcess.running = true
  }

  Process { id: openProcess; running: false }

  function openVerificationPage() {
    if (openProcess.running) return
    // Re-checked here rather than trusted from the property. `verificationUri`
    // already filters, but this is the line that hands a string to a URL
    // handler, and that is where the guarantee has to hold — a later edit that
    // loosens the property should not silently widen what gets opened.
    var url = isDeviceLoginUrl(root.verificationUri) ? root.verificationUri : root.deviceLoginUrl
    openProcess.command = ["xdg-open", url]
    openProcess.running = true
  }

  Process { id: copyProcess; running: false }

  function copyCode() {
    if (root.userCode === "" || copyProcess.running) return
    copyProcess.command = ["wl-copy", "--", root.userCode]
    copyProcess.running = true
  }

  // ------------------------------------------------------------ formatting

  function formatCount(value) {
    var n = Number(value)
    if (!isFinite(n)) return "0"
    if (n >= 1000000) return (n / 1000000).toFixed(1).replace(/\.0$/, "") + "M"
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k"
    return String(Math.round(n))
  }

  function formatResetDate(value) {
    var text = String(value || "")
    if (text === "") return ""
    var parsed = new Date(text + "T00:00:00")
    if (isNaN(parsed.getTime())) return text
    return ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][parsed.getMonth()]
      + " " + parsed.getDate()
  }

  // "resets in 3d" reads better than a date you have to subtract from today,
  // but only while the window is short enough for that to mean anything.
  function formatResetCountdown() {
    var ms = root.resetMs
    if (!(ms > 0)) return root.resetDate === "" ? "" : "resets " + formatResetDate(root.resetDate)
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return "resets in " + days + "d"
    if (hours > 0) return "resets in " + hours + "h"
    return "resets in " + Math.max(1, minutes) + "m"
  }

  function dayLabel(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return ""
    return ["S", "M", "T", "W", "T", "F", "S"][parsed.getDay()]
  }

  function dayTooltip(day) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var count = Number(day.requests || 0)
    var label = isNaN(parsed.getTime()) ? String(day.date)
      : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
        + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    return label + " · " + count + (count === 1 ? " request" : " requests")
  }

  // What the panel says under the title. Ordered by what blocks you next:
  // a missing binary before a missing unit, a stopped proxy before a
  // sign-in, since each one is a prerequisite for the next.
  readonly property string statusText: {
    if (!everLoaded) return "Checking"
    if (!proxyInstalled) return "copilot-proxy-api not installed"
    if (!unitInstalled) return "Service not installed"
    if (failed) return "Service failed"
    if (activating) return "Starting"
    if (!running) return "Stopped"
    if (!reachable) return "Starting"
    if (authPending) return "Waiting for GitHub"
    if (!authenticated) return "Not signed in"
    if (!ready) return "Connecting to Copilot"
    if (githubUser !== "") return githubUser
    return "Running"
  }
}
