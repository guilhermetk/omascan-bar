import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A scanner in the bar. Left click scans one page (or the feeder) with the
// scanner and settings OmaScan has saved, and says where the file went; a
// click while scanning cancels. Right click opens OmaScan itself.
//
// All the scanning is `omascan scan --json`: this widget only starts it and
// reads the one line it prints. Exit codes, from OmaScan's README:
//   0 saved · 1 bad arguments or not written · 2 no scanner chosen yet
//   3 scanner busy · 4 scan failed · 130 cancelled
BarWidget {
  id: root
  moduleName: "guilhermetk.omascan"

  // One bar per monitor means one widget per monitor. The widget that was
  // clicked runs the scan; `scanning` is mirrored to the others so every
  // bar shows it, and a click on any of them cancels it.
  property bool scanning: false
  // Whether this OmaScan has the scan command (0.1.1 and older open the
  // window instead). Checked once, before the first scan.
  property string support: "unknown" // unknown | checking | yes | old | missing
  property bool scanAfterCheck: false

  property int exitCode: -1
  property string output: ""
  property bool exited: false
  property bool outputDone: false

  readonly property string scannerGlyph: String.fromCodePoint(0xF06AB) // nf-md-scanner
  readonly property string waitingGlyph: String.fromCodePoint(0xF051F) // nf-md-timer_sand

  // The command setting, with ~ spelled out: nothing here goes through a
  // shell that would expand it.
  readonly property string command: {
    var value = String(root.setting("command", "omascan")).trim()
    if (value === "") value = "omascan"
    if (value === "~" || value.indexOf("~/") === 0) value = Quickshell.env("HOME") + value.substring(1)
    return value
  }
  readonly property var formatArgs: {
    var format = root.setting("format", "Saved choice")
    if (format === "PDF") return ["--format", "pdf"]
    if (format === "PNG") return ["--format", "png"]
    return []
  }

  // Through a login shell, as Util.execArgv does, for the session's PATH;
  // `exec "$@"` keeps every argument literal.
  function argv(args) {
    return ["bash", "-lc", 'exec "$@"', "bash", root.command].concat(args)
  }

  function notify(title, body, urgency) {
    Util.execArgv(["notify-send", "--app-name=OmaScan", "--icon=omascan",
                   "--urgency=" + (urgency || "normal"), title, body || ""])
  }

  // The window, or the one already open: OmaScan allows only one.
  function openApp() {
    // omarchy-launch-or-focus evals the launch command, so the path is quoted.
    var quoted = "'" + root.command.replace(/'/g, "'\\''") + "'"
    Util.execArgv(["omarchy-launch-or-focus", "omascan", "uwsm-app -- " + quoted])
  }

  function scanOrCancel() {
    if (root.anyScanning()) {
      root.broadcast("cancelScan")
      return
    }
    if (root.support === "yes") {
      root.startScan()
    } else if (root.support !== "checking") {
      root.scanAfterCheck = true
      root.support = "checking"
      checkProc.command = ["bash", "-lc", 'command -v "$1" >/dev/null || exit 127; exec "$1" --help',
                           "bash", root.command]
      checkProc.running = true
    }
  }

  function anyScanning() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : [root]
    for (var i = 0; i < items.length; i++)
      if (items[i] && items[i].scanning) return true
    return false
  }

  function startScan() {
    root.exitCode = -1
    root.output = ""
    root.exited = false
    root.outputDone = false
    scanProc.command = root.argv(["scan", "--json"].concat(root.formatArgs))
    scanProc.running = true
    root.broadcast("markScanning")
  }

  // Peers: show the scan another bar started, and cancel it from any bar.
  function markScanning() { root.scanning = true }
  function markIdle() { root.scanning = false }
  function cancelScan() {
    // Quickshell stops a process with SIGTERM, which OmaScan takes as
    // "cancel": it stops the scanner cleanly and exits 130.
    if (scanProc.running) scanProc.running = false
  }

  function tryFinish() {
    if (!root.exited || !root.outputDone) return
    root.broadcast("markIdle")

    var result = {}
    try {
      result = JSON.parse(String(root.output).trim().split("\n").pop() || "{}")
    } catch (e) {
      result = {}
    }
    var message = result.message ? String(result.message) : ""
    var files = Array.isArray(result.files) ? result.files : []

    if (root.exitCode === 0 || (root.exitCode === 4 && files.length > 0)) {
      root.announce(files, result.pages || files.length, root.exitCode === 0 ? "" : message)
    } else if (root.exitCode === 2) {
      root.notify("Pick a scanner first", "OmaScan is asking which scanner to use.")
      Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", root.command, "setup"])
    } else if (root.exitCode === 3) {
      root.notify("Scanner busy", message || "Another scan, or another app, is using the scanner.")
    } else if (root.exitCode === 130 || result.error === "cancelled") {
      root.notify("Scan cancelled", "")
    } else {
      root.notify("Scan failed", message || ("OmaScan stopped with code " + root.exitCode + "."), "critical")
    }
  }

  // Where it went, in words, with a click on the toast opening the file.
  function announce(files, pages, problem) {
    if (files.length === 0) return
    var first = String(files[0])
    var name = first.split("/").pop()
    var folder = first.substring(0, first.lastIndexOf("/"))
    var home = Quickshell.env("HOME")
    if (folder === home) folder = "~"
    else if (folder.indexOf(home + "/") === 0) folder = "~" + folder.substring(home.length)
    var body = files.length > 1
      ? files.length + " pictures, from " + name + ", in " + folder
      : (pages > 1 ? pages + " pages in " : "") + name + (pages > 1 ? ", " : " in ") + folder
    if (problem !== "") body += "\n" + problem
    openProc.file = first
    openProc.command = ["notify-send", "--app-name=OmaScan", "--icon=omascan",
                        "--action=default=Open", problem !== "" ? "Scan stopped early" : "Scanned", body]
    openProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: checkProc
    stdout: StdioCollector {
      id: checkOut
      waitForEnd: true
    }
    onExited: function(code) {
      // The window's own --help prints and exits; one that knows `scan`
      // lists the commands.
      var text = String(checkOut.text || "")
      root.support = code === 127 ? "missing"
        : (code === 0 && text.indexOf("scan") >= 0 && text.indexOf("omascan help") >= 0 ? "yes" : "old")
      var wanted = root.scanAfterCheck
      root.scanAfterCheck = false
      if (root.support === "yes") {
        if (wanted) root.startScan()
      } else if (root.support === "missing") {
        root.notify("OmaScan is not installed", "Install it from github.com/guilhermetk/omascan, or set its command in this widget's settings.", "critical")
        root.support = "unknown" // look again next time
      } else {
        root.notify("OmaScan needs updating", "This widget needs OmaScan 0.2 or newer, which can scan from the bar.", "critical")
        root.support = "unknown"
      }
    }
  }

  Process {
    id: scanProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.output = String(text || "")
        root.outputDone = true
        root.tryFinish()
      }
    }
    onExited: function(code) {
      root.exitCode = code
      root.exited = true
      root.tryFinish()
    }
  }

  // Waits on the toast: notify-send prints the action picked, if any.
  Process {
    id: openProc
    property string file: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim() === "default" && openProc.file !== "")
          Util.execArgv(["xdg-open", openProc.file])
      }
    }
  }

  IpcHandler {
    target: "guilhermetk.omascan"

    // For a key binding: omarchy-shell guilhermetk.omascan scan
    function scan(): void { root.scanOrCancel() }
    function cancel(): void { root.broadcast("cancelScan") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.scanning ? root.waitingGlyph : root.scannerGlyph
    tooltipText: root.scanning
      ? "Scanning… click to cancel"
      : "Scan a page · right-click to open OmaScan"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openApp()
      else if (b === Qt.LeftButton) root.scanOrCancel()
    }
  }
}
