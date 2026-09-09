import QtQuick
import QtQuick.Controls as CC
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Peek.js" as Peek

Item {
  id: root

  property bool opened: false
  property bool busy: false
  property string errorText: ""

  property string engineBin: Quickshell.env("HOME") + "/.local/bin/omysql-engine"

  property string view: "profiles"
  property var profiles: []
  property var databases: []
  property var tables: []
  property var activeProfile: null
  property string database: ""
  property string table: ""

  property string profileFilter: ""
  property string databaseFilter: ""
  property string tableFilter: ""
  readonly property string activeFilter: view === "profiles" ? profileFilter : view === "databases" ? databaseFilter : view === "tables" ? tableFilter : ""
  property int selectedIndex: 0
  property bool searchOpen: false
  property string searchTerm: ""
  property bool queryOpen: false
  property bool isQueryResult: false
  property string lastSql: ""

  property bool formNew: true
  property var formProfile: null
  property bool deleteConfirmOpen: false
  property string deleteName: ""

  property bool rowDetail: false
  property int detailRow: -1
  property var detailPairs: []
  property double escArmedAt: 0
  property bool escWarn: false

  property var columns: []
  property var rows: []
  property var colWidths: []
  property double tableTotal: 0
  property double offset: 0
  property double limit: 50
  property bool truncated: false
  readonly property int shown: rows.length

  readonly property double tableWidth: {
    var sum = 0
    for (var i = 0; i < colWidths.length; i++) sum += colWidths[i]
    return Math.max(sum, 1)
  }

  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property color rowStripe: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.035)
  readonly property color rule: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding

  readonly property var items: {
    var src = []
    var i = 0
    if (view === "profiles") {
      for (i = 0; i < profiles.length; i++) {
        var p = profiles[i]
        src.push({ label: p.name, sub: p.user + "@" + p.host + (p.database ? "  ·  " + p.database : ""), profile: p })
      }
    } else if (view === "databases") {
      for (i = 0; i < databases.length; i++) src.push({ label: databases[i], sub: "" })
    } else if (view === "tables") {
      for (i = 0; i < tables.length; i++) src.push({ label: tables[i], sub: "" })
    }
    if (view === "profiles" && profileFilter !== "") {
      var np = profileFilter.toLowerCase()
      src = src.filter(function (it) { return it.label.toLowerCase().indexOf(np) >= 0 })
    } else if (view === "databases" && databaseFilter !== "") {
      var nd = databaseFilter.toLowerCase()
      src = src.filter(function (it) { return it.label.toLowerCase().indexOf(nd) >= 0 })
    } else if (view === "tables" && tableFilter !== "") {
      var nt = tableFilter.toLowerCase()
      src = src.filter(function (it) { return it.label.toLowerCase().indexOf(nt) >= 0 })
    }
    return src
  }

  readonly property string titleText: {
    if (view === "profiles") return "Connections"
    if (view === "form") return formNew ? "New connection" : "Edit connection"
    if (view === "databases") return "Databases"
    if (view === "tables") return "Tables"
    if (view === "rows" && rowDetail && detailRow >= 0)
      return (isQueryResult ? "Query result" : table) + "  ·  row " + (detailRow + 1)
    return isQueryResult ? "Query result" : table
  }

  readonly property string breadcrumbText: {
    if (view === "form") return ""
    var parts = []
    if (activeProfile) parts.push(activeProfile.name)
    if (database !== "") parts.push(database)
    if (view === "rows" && !isQueryResult && table !== "") parts.push(table)
    return parts.join("  ›  ")
  }

  readonly property string hintText: {
    if (escWarn) return "press esc again to go back"
    if (view === "rows") {
      if (rowDetail) return "↑ ↓ field · ← → row · ⏎ or esc back to data"
      if (isQueryResult) return "⏎ row · r re-run · ⇧R fresh table · esc esc back"
      return "⏎ row · / search · q sql · ← → page · r refresh · ⇧R fresh · esc esc back"
    }
    if (view === "form") return "⏎ next field · last field saves · esc cancel"
    if (view === "profiles") return "n new · e edit · d delete · ⏎ open · esc back"
    return "type to filter · ⏎ open · r refresh · esc back"
  }

  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    root.opened = true
    root.errorText = ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    var payload = null
    try { payload = payloadJson ? JSON.parse(payloadJson) : null } catch (e) { payload = null }
    if (payload && payload.profile) {
      root.activeProfile = { name: String(payload.profile), host: "", port: "", user: "", database: payload.database ? String(payload.database) : "" }
      if (payload.table) {
        root.database = payload.database ? String(payload.database) : ""
        root.table = String(payload.table)
        root.isQueryResult = false
        root.offset = 0
        root.selectedIndex = 0
        root.view = "rows"
        root.fetchRows()
      } else if (root.activeProfile.database) {
        root.openDatabase(root.activeProfile.database)
      } else {
        root.view = "databases"
        root.selectedIndex = 0
        root.fetchDatabases()
      }
      return
    }
    if (root.profiles.length === 0) root.fetchProfiles()
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  IpcHandler {
    target: "madddtone.gomysql-peek"

    function open(): void { root.open("{}") }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  property var pendingCb: null
  property var queuedArgs: null
  property var queuedCb: null

  function run(args, cb) {
    if (root.busy) {
      root.queuedArgs = args
      root.queuedCb = cb
      return
    }
    root.busy = true
    root.errorText = ""
    root.pendingCb = cb
    engineProc.command = [root.engineBin].concat(args)
    engineProc.running = true
  }

  Process {
    id: engineProc
    command: []

    stdout: StdioCollector {
      id: engineStdout
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: engineStderr
      waitForEnd: true
    }

    onExited: function (exitCode) {
      root.busy = false
      var cb = root.pendingCb
      root.pendingCb = null
      if (exitCode !== 0) {
        var msg = String(engineStderr.text || "").replace(/\s+/g, " ").trim()
        root.errorText = msg || ("engine failed (exit " + exitCode + ")")
        if (cb) cb(null)
      } else {
        var parsed = Peek.parseEngine(String(engineStdout.text || ""))
        if (!parsed.ok) {
          root.errorText = parsed.error
          if (cb) cb(null)
        } else if (cb) {
          cb(parsed.data)
        }
      }
      if (root.queuedArgs) {
        var args = root.queuedArgs
        var queued = root.queuedCb
        root.queuedArgs = null
        root.queuedCb = null
        root.run(args, queued)
      }
    }
  }

  Timer {
    id: escWarnTimer
    interval: 2000
    onTriggered: {
      root.escWarn = false
      root.escArmedAt = 0
    }
  }

  function fetchProfiles() {
    run(["profiles"], function (data) {
      if (!data) return
      root.profiles = data.profiles || []
    })
  }

  function openProfile(p) {
    root.activeProfile = p
    root.database = p.database || ""
    root.table = ""
    root.databaseFilter = ""
    root.tableFilter = ""
    root.selectedIndex = 0
    root.view = "databases"
    root.fetchDatabases()
  }

  function openForm(mode) {
    if (root.busy) return
    var it = mode === "edit" ? root.items[root.selectedIndex] : null
    if (mode === "edit" && (!it || !it.profile)) return
    root.errorText = ""
    root.view = "form"
    if (mode === "new") {
      root.formNew = true
      root.formProfile = null
      nameField.text = ""
      hostField.text = ""
      portField.text = "3306"
      userField.text = ""
      passwordField.text = ""
      databaseField.text = ""
      Qt.callLater(function () { nameField.forceActiveFocus() })
      return
    }
    root.formNew = false
    root.formProfile = it.profile
    run(["profile", "get", "--name", it.profile.name], function (data) {
      if (!data) {
        root.view = "profiles"
        return
      }
      var p = data.profile || {}
      nameField.text = p.name || ""
      hostField.text = p.host || ""
      portField.text = p.port || "3306"
      userField.text = p.user || ""
      passwordField.text = p.password || ""
      databaseField.text = p.database || ""
      Qt.callLater(function () { nameField.forceActiveFocus() })
    })
  }

  function cancelForm() {
    root.view = "profiles"
    root.errorText = ""
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function saveForm() {
    if (root.busy) return
    var name = nameField.text.trim()
    var host = hostField.text.trim()
    if (name === "" || host === "") {
      root.errorText = "name and host are required"
      return
    }
    var port = portField.text.trim()
    if (port === "") port = "3306"
    var args = ["profile", "save", "--name", name, "--host", host,
      "--port", port, "--user", userField.text.trim(),
      "--password", passwordField.text,
      "--database", databaseField.text.trim()]
    var saved = { name: name, host: host, port: port,
      user: userField.text.trim(), password: passwordField.text,
      database: databaseField.text.trim() }
    run(args, function (data) {
      if (!data) return
      root.fetchProfiles()
      root.openProfile(saved)
    })
  }

  function requestDelete() {
    if (root.busy || root.view !== "profiles") return
    var it = root.items[root.selectedIndex]
    if (!it || !it.profile) return
    root.deleteName = it.profile.name
    root.deleteConfirmOpen = true
  }

  function deleteSelected() {
    if (root.busy) return
    var name = root.deleteName
    root.deleteName = ""
    run(["profile", "remove", "--name", name], function (data) {
      if (!data) return
      root.fetchProfiles()
    })
  }

  function fetchDatabases() {
    run(["dbs", "--profile", root.activeProfile.name], function (data) {
      if (!data) return
      root.databases = data.databases || []
    })
  }

  function openDatabase(db) {
    root.database = db
    root.table = ""
    root.tableFilter = ""
    root.selectedIndex = 0
    root.view = "tables"
    root.fetchTables()
  }

  function fetchTables() {
    run(["tables", "--profile", root.activeProfile.name, "--db", root.database], function (data) {
      if (!data) return
      root.tables = data.tables || []
    })
  }

  function openTable(t) {
    root.table = t
    root.isQueryResult = false
    root.lastSql = ""
    root.searchOpen = false
    root.searchTerm = ""
    root.queryOpen = false
    root.offset = 0
    root.selectedIndex = 0
    root.closeRowDetail()
    root.escArmedAt = 0
    root.escWarn = false
    root.view = "rows"
    root.fetchRows()
  }

  function fetchRows() {
    var args = ["rows", "--profile", root.activeProfile.name, "--db", root.database,
      "--table", root.table, "--limit", String(root.limit), "--offset", String(root.offset)]
    if (root.searchOpen && root.searchTerm !== "") args = args.concat(["--search", root.searchTerm])
    run(args, function (data) {
      if (!data) return
      root.columns = data.columns || []
      root.rows = data.rows || []
      root.tableTotal = data.total || 0
      root.offset = data.offset || 0
      root.truncated = !!data.truncated
      root.applyWidths()
      if (root.rowDetail) {
        if (root.detailRow >= 0 && root.detailRow < root.rows.length) {
          root.buildDetail()
          if (root.selectedIndex >= root.detailPairs.length) root.selectedIndex = 0
        } else root.closeRowDetail()
      }
    })
  }

  function applyWidths() {
    var charW = Math.max(6, Math.round(Style.font.bodySmall * 0.62))
    root.colWidths = Peek.computeWidths(root.columns, root.rows, charW, Style.space(44), Style.space(320), Style.space(10))
  }

  function runQuery() {
    var sqlText = queryEntry.text.trim()
    if (sqlText === "") return
    var args = ["query", "--profile", root.activeProfile.name, "--db", root.database, "--sql", sqlText]
    run(args, function (data) {
      if (!data) return
      root.columns = data.columns || []
      root.rows = data.rows || []
      root.tableTotal = data.total || 0
      root.offset = 0
      root.truncated = !!data.truncated
      root.isQueryResult = true
      root.lastSql = sqlText
      root.applyWidths()
      root.selectedIndex = 0
      if (root.rowDetail) {
        if (root.detailRow < root.rows.length) {
          root.buildDetail()
        } else root.closeRowDetail()
      }
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    })
  }

  function applySearch() {
    root.searchTerm = searchEntry.text.trim()
    root.offset = 0
    root.selectedIndex = 0
    root.fetchRows()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function openSearch() {
    if (root.isQueryResult) return
    root.searchOpen = true
    root.searchTerm = searchTerm
    searchEntry.text = searchTerm
    root.queryOpen = false
    Qt.callLater(function () { searchEntry.forceActiveFocus() })
  }

  function openQuery() {
    root.queryOpen = true
    root.searchOpen = false
    if (root.isQueryResult && root.lastSql !== "") queryEntry.text = root.lastSql
    Qt.callLater(function () { queryEntry.forceActiveFocus() })
  }

  function closeInputs() {
    var hadSearch = root.searchOpen && root.searchTerm !== ""
    root.searchOpen = false
    root.searchTerm = ""
    root.queryOpen = false
    if (hadSearch && root.view === "rows" && !root.isQueryResult) {
      root.offset = 0
      root.fetchRows()
    }
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function openRowDetail() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.rows.length) return
    root.detailRow = root.selectedIndex
    root.rowDetail = true
    root.buildDetail()
    root.selectedIndex = 0
    Qt.callLater(function () { detailList.positionViewAtIndex(0, ListView.Beginning) })
  }

  function buildDetail() {
    var pairs = []
    var rowData = root.rows[root.detailRow] || []
    for (var i = 0; i < root.columns.length; i++) {
      pairs.push({ field: root.columns[i], value: rowData[i] })
    }
    root.detailPairs = pairs
  }

  function closeRowDetail() {
    root.rowDetail = false
    root.detailRow = -1
    root.detailPairs = []
  }

  function detailSelect(delta) {
    var count = root.detailPairs.length
    if (count === 0) return
    root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
    detailList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function detailRowShift(delta) {
    var newRow = root.detailRow + delta
    if (newRow < 0 || newRow >= root.rows.length) return
    root.detailRow = newRow
    root.buildDetail()
    if (root.selectedIndex >= root.detailPairs.length) root.selectedIndex = 0
    detailList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function reloadFresh() {
    if (root.busy) return
    root.isQueryResult = false
    root.lastSql = ""
    root.queryOpen = false
    queryEntry.text = ""
    root.searchOpen = false
    root.searchTerm = ""
    root.offset = 0
    root.selectedIndex = 0
    root.closeRowDetail()
    root.fetchRows()
  }

  function prevPage() {
    if (root.isQueryResult || root.busy) return
    if (root.offset > 0) {
      root.offset = Math.max(0, root.offset - root.limit)
      root.selectedIndex = 0
      root.fetchRows()
    }
  }

  function nextPage() {
    if (root.isQueryResult || root.busy) return
    if (root.offset + root.shown < root.tableTotal) {
      root.offset += root.limit
      root.selectedIndex = 0
      root.fetchRows()
    }
  }

  function goBack() {
    if (root.busy) return
    if (searchEntry.activeFocus || queryEntry.activeFocus) {
      root.closeInputs()
      return
    }
    if (root.view === "form") {
      root.cancelForm()
      return
    }
    if (root.view === "rows") {
      if (root.rowDetail) {
        root.closeRowDetail()
        return
      }
      var now = Date.now()
      if (now - root.escArmedAt < 2000) {
        root.escArmedAt = 0
        root.escWarn = false
        if (root.isQueryResult) root.isQueryResult = false
        root.view = "tables"
        root.selectedIndex = 0
        if (root.tables.length === 0) root.fetchTables()
        return
      }
      root.escArmedAt = now
      root.escWarn = true
      escWarnTimer.restart()
      return
    }
    if (root.view === "tables") {
      root.view = "databases"
      root.selectedIndex = 0
      if (root.databases.length === 0) root.fetchDatabases()
      return
    }
    if (root.view === "databases") {
      root.view = "profiles"
      root.selectedIndex = 0
      return
    }
    root.close()
  }

  function refresh() {
    if (root.busy) return
    if (root.view === "profiles") root.fetchProfiles()
    else if (root.view === "databases") root.fetchDatabases()
    else if (root.view === "tables") root.fetchTables()
    else if (root.isQueryResult) {
      queryEntry.text = root.lastSql
      root.runQuery()
    } else root.fetchRows()
  }

  function activate() {
    if (root.busy) return
    if (root.view === "form") return
    if (root.view === "rows") {
      if (queryEntry.activeFocus) { root.runQuery(); return }
      if (searchEntry.activeFocus) { root.applySearch(); return }
      if (root.rowDetail) { root.closeRowDetail(); return }
      root.openRowDetail()
      return
    }
    var it = root.items[root.selectedIndex]
    if (!it) return
    if (root.view === "profiles") root.openProfile(it.profile)
    else if (root.view === "databases") root.openDatabase(it.label)
    else if (root.view === "tables") root.openTable(it.label)
  }

  function select(delta) {
    if (root.view === "rows") {
      if (root.rowDetail) {
        root.detailSelect(delta)
        return
      }
      var max = root.rows.length - 1
      if (max < 0) return
      root.selectedIndex = Math.max(0, Math.min(max, root.selectedIndex + delta))
      rowsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
      return
    }
    var count = root.items.length
    if (count === 0) return
    root.selectedIndex = Math.max(0, Math.min(count - 1, root.selectedIndex + delta))
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectFirst() {
    if (root.rowDetail) {
      root.selectedIndex = 0
      detailList.positionViewAtIndex(0, ListView.Beginning)
      return
    }
    root.selectedIndex = 0
    if (root.view === "rows") rowsList.positionViewAtIndex(0, ListView.Beginning)
    else list.positionViewAtIndex(0, ListView.Beginning)
  }

  function selectLast() {
    if (root.rowDetail) {
      root.selectedIndex = root.detailPairs.length - 1
      if (root.selectedIndex < 0) return
      detailList.positionViewAtIndex(root.selectedIndex, ListView.End)
      return
    }
    var count = root.view === "rows" ? root.rows.length : root.items.length
    if (count === 0) return
    root.selectedIndex = count - 1
    if (root.view === "rows") rowsList.positionViewAtIndex(count - 1, ListView.End)
    else list.positionViewAtIndex(count - 1, ListView.End)
  }

  function setFilter(text) {
    if (root.view === "profiles") root.profileFilter = text
    else if (root.view === "databases") root.databaseFilter = text
    else if (root.view === "tables") root.tableFilter = text
    root.selectedIndex = 0
  }

  function emptyText() {
    if (busy) return "loading…"
    if (view === "profiles") return profiles.length === 0 ? "No connections — add one with gomysql first" : "No matches for “" + activeFilter + "”"
    if (view === "databases") return databases.length === 0 ? "No databases visible for this user" : "No matches for “" + activeFilter + "”"
    if (view === "tables") return tables.length === 0 ? "No tables in " + database : "No matches for “" + activeFilter + "”"
    if (errorText !== "") return ""
    return "No rows"
  }

  onItemsChanged: {
    if (root.view === "rows") return
    if (root.selectedIndex >= root.items.length) root.selectedIndex = 0
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-gomysql"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1150), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea {
        anchors.fill: parent
        onClicked: {
        }
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (root.deleteConfirmOpen) {
            deleteConfirm.handleKey(event)
            event.accepted = true
            return
          }
          if (event.key !== Qt.Key_Escape) {
            root.escArmedAt = 0
            root.escWarn = false
          }
          if (event.key === Qt.Key_Escape) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_N && root.view === "profiles") {
            root.openForm("new")
            event.accepted = true
          } else if (event.key === Qt.Key_E && root.view === "profiles") {
            root.openForm("edit")
            event.accepted = true
          } else if (event.key === Qt.Key_D && root.view === "profiles") {
            root.requestDelete()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-8)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(8)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectFirst()
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectLast()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate()
            event.accepted = true
          } else if (event.key === Qt.Key_Left && root.view === "rows") {
            if (root.rowDetail) root.detailRowShift(-1)
            else root.prevPage()
            event.accepted = true
          } else if (event.key === Qt.Key_Right && root.view === "rows") {
            if (root.rowDetail) root.detailRowShift(1)
            else root.nextPage()
            event.accepted = true
          } else if (event.key === Qt.Key_Slash && root.view === "rows") {
            root.openSearch()
            event.accepted = true
          } else if (event.key === Qt.Key_Q && root.view === "rows") {
            root.openQuery()
            event.accepted = true
          } else if (event.key === Qt.Key_R && root.view === "rows") {
            if (event.modifiers & Qt.ShiftModifier) root.reloadFresh()
            else root.refresh()
            event.accepted = true
          } else if (root.view !== "rows") {
            if (Util.editsFilter(event, root.activeFilter)) {
              root.setFilter(Util.editedFilter(event, root.activeFilter))
              event.accepted = true
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.setFilter(root.activeFilter + event.text)
              event.accepted = true
            }
          }
        }

        Item {
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset

          Item {
            id: headerItem
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: headerColumn.implicitHeight

            Column {
              id: headerColumn
              anchors.left: parent.left
              anchors.right: metaText.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                text: root.titleText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                visible: root.breadcrumbText !== ""
                text: root.breadcrumbText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                width: parent.width
              }
            }

            Text {
              id: metaText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.busy ? "loading…" : root.hintText
              color: root.busy ? root.selectedText : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            id: errorText
            textFormat: Text.PlainText
            visible: root.errorText !== ""
            anchors.top: headerItem.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? implicitHeight : 0
            text: root.errorText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            id: separator
            anchors.top: errorText.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            foreground: root.foreground
          }

          Item {
            id: inputBar
            visible: root.view === "rows" && (root.searchOpen || root.queryOpen)
            anchors.top: separator.bottom
            anchors.topMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right
            height: visible ? Math.max(searchEntry.implicitHeight, queryEntry.implicitHeight) : 0

            RowLayout {
              anchors.fill: parent
              spacing: Style.space(6)

              TextField {
                id: searchEntry
                visible: root.searchOpen
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Search all columns…  (⏎ apply · esc close)"
                onAccepted: root.applySearch()
                Keys.onEscapePressed: root.closeInputs()
              }

              TextField {
                id: queryEntry
                visible: root.queryOpen
                Layout.fillWidth: true
                foreground: root.foreground
                placeholderText: "Read-only SQL…  (⏎ run · esc close)"
                onAccepted: root.runQuery()
                Keys.onEscapePressed: root.closeInputs()
              }
            }
          }

          Item {
            id: contentArea
            anchors.top: inputBar.bottom
            anchors.topMargin: Style.space(4)
            anchors.bottom: footer.top
            anchors.bottomMargin: Style.space(4)
            anchors.left: parent.left
            anchors.right: parent.right

            Flickable {
              id: hscroll
              anchors.fill: parent
              visible: root.view === "rows" && !root.rowDetail
              clip: true
              contentWidth: Math.max(root.tableWidth, hscroll.width)
              contentHeight: hscroll.height
              interactive: false
              boundsBehavior: Flickable.StopAtBounds
              CC.ScrollBar.horizontal: CC.ScrollBar {
                policy: root.tableWidth > hscroll.width ? CC.ScrollBar.AsNeeded : CC.ScrollBar.AlwaysOff
              }

              WheelHandler {
                id: wheelVertical
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                  if (root.rowDetail) return
                  if (event.angleDelta.y === 0) return
                  if ((event.modifiers & Qt.ShiftModifier) !== 0) {
                    var mx = Math.max(0, root.tableWidth - hscroll.width)
                    hscroll.contentX = Math.max(0, Math.min(hscroll.contentX - event.angleDelta.y / 2, mx))
                  } else {
                    root.select(event.angleDelta.y > 0 ? -3 : 3)
                  }
                  event.accepted = true
                }
              }

              WheelHandler {
                id: wheelHorizontal
                orientation: Qt.Horizontal
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                  if (root.rowDetail) return
                  if (event.angleDelta.x === 0) return
                  var mx = Math.max(0, root.tableWidth - hscroll.width)
                  hscroll.contentX = Math.max(0, Math.min(hscroll.contentX - event.angleDelta.x / 2, mx))
                  event.accepted = true
                }
              }

              Column {
                width: hscroll.contentWidth
                spacing: 0

                Rectangle {
                  width: parent.width
                  height: Style.space(30)
                  color: root.rowStripe

                  Row {
                    anchors.fill: parent
                    Repeater {
                      model: root.columns.length

                      delegate: Item {
                        required property int index
                        width: root.colWidths[index] || 80
                        height: parent.height

                        Text {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(4)
                          anchors.rightMargin: Style.space(4)
                          verticalAlignment: Text.AlignVCenter
                          textFormat: Text.PlainText
                          text: root.columns[index] || ""
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: root.rule
                }

                ListView {
                  id: rowsList
                  width: parent.width
                  height: hscroll.height - Style.space(30) - 1
                  clip: true
                  interactive: false
                  boundsBehavior: Flickable.StopAtBounds
                  CC.ScrollBar.vertical: CC.ScrollBar {
                    policy: rowsList.contentHeight > rowsList.height ? CC.ScrollBar.AsNeeded : CC.ScrollBar.AlwaysOff
                  }

                  model: root.rows.length

                  delegate: Rectangle {
                    id: rowDelegate
                    required property int index
                    readonly property var rowData: root.rows[index] || []
                    width: root.tableWidth
                    height: Style.space(30)
                    color: index === root.selectedIndex ? root.selectedBackground : (index % 2 === 1 ? root.rowStripe : "transparent")

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) root.selectedIndex = rowDelegate.index
                      onClicked: root.selectedIndex = rowDelegate.index
                    }

                    Row {
                      anchors.fill: parent

                      Repeater {
                        model: root.columns.length

                        delegate: Item {
                          id: cellItem
                          required property int index
                          width: root.colWidths[index] || 80
                          height: parent.height

                          Text {
                            anchors.fill: parent
                            anchors.leftMargin: Style.space(4)
                            anchors.rightMargin: Style.space(4)
                            verticalAlignment: Text.AlignVCenter
                            textFormat: Text.PlainText
                             text: Peek.fmtCell(rowDelegate.rowData[cellItem.index])
                             color: Peek.isNull(rowDelegate.rowData[cellItem.index]) ? root.dim : (rowDelegate.index === root.selectedIndex ? root.selectedText : root.foreground)
                             font.family: root.fontFamily
                             font.pixelSize: Style.font.bodySmall
                             font.italic: Peek.isNull(rowDelegate.rowData[cellItem.index])
                             elide: Text.ElideRight
                           }
                         }
                       }
                     }
                   }
                 }
               }
             }

             Item {
               id: detailContainer
               anchors.fill: parent
               visible: root.rowDetail

               readonly property int fieldWidth: {
                 var charW = Math.max(6, Math.round(Style.font.bodySmall * 0.62))
                 var max = 5
                 for (var i = 0; i < root.detailPairs.length; i++) {
                   max = Math.max(max, String(root.detailPairs[i].field).length)
                 }
                 return Math.min(Math.max(Style.space(110), max * charW + Style.space(12)), Math.max(Style.space(110), width / 2.4))
               }

               Rectangle {
                 width: parent.width
                 height: Style.space(30)
                 color: root.rowStripe

                 Text {
                   textFormat: Text.PlainText
                   anchors.left: parent.left
                   anchors.leftMargin: Style.space(4)
                   anchors.verticalCenter: parent.verticalCenter
                   width: detailContainer.fieldWidth - Style.space(8)
                   text: "Field"
                   color: root.foreground
                   font.family: root.fontFamily
                   font.pixelSize: Style.font.bodySmall
                   font.bold: true
                   elide: Text.ElideRight
                 }

                 Text {
                   textFormat: Text.PlainText
                   anchors.left: parent.left
                   anchors.leftMargin: detailContainer.fieldWidth
                   anchors.right: parent.right
                   anchors.rightMargin: Style.space(4)
                   anchors.verticalCenter: parent.verticalCenter
                   text: "Value"
                   color: root.foreground
                   font.family: root.fontFamily
                   font.pixelSize: Style.font.bodySmall
                   font.bold: true
                   elide: Text.ElideRight
                 }
               }

               Rectangle {
                 width: parent.width
                 height: 1
                 color: root.rule
               }

               ListView {
                 id: detailList
                 anchors.top: parent.top
                 anchors.topMargin: Style.space(31)
                 anchors.bottom: parent.bottom
                 anchors.left: parent.left
                 anchors.right: parent.right
                 clip: true
                 boundsBehavior: Flickable.StopAtBounds
                 model: root.detailPairs.length
                 CC.ScrollBar.vertical: CC.ScrollBar {
                   policy: detailList.contentHeight > detailList.height ? CC.ScrollBar.AsNeeded : CC.ScrollBar.AlwaysOff
                 }

                 delegate: Rectangle {
                   id: detailRowItem
                   required property int index
                   width: detailList.width
                   height: Style.space(30)
                   color: index === root.selectedIndex ? root.selectedBackground : (index % 2 === 1 ? root.rowStripe : "transparent")

                   MouseArea {
                     anchors.fill: parent
                     hoverEnabled: true
                     onContainsMouseChanged: if (containsMouse) root.selectedIndex = detailRowItem.index
                     onClicked: root.selectedIndex = detailRowItem.index
                   }

                   Text {
                     textFormat: Text.PlainText
                     anchors.left: parent.left
                     anchors.leftMargin: Style.space(4)
                     anchors.verticalCenter: parent.verticalCenter
                     width: detailContainer.fieldWidth - Style.space(8)
                     text: root.detailPairs[detailRowItem.index] ? root.detailPairs[detailRowItem.index].field : ""
                     color: detailRowItem.index === root.selectedIndex ? root.selectedText : root.foreground
                     font.family: root.fontFamily
                     font.pixelSize: Style.font.bodySmall
                     font.bold: true
                     elide: Text.ElideRight
                   }

                   Text {
                     textFormat: Text.PlainText
                     anchors.left: parent.left
                     anchors.leftMargin: detailContainer.fieldWidth
                     anchors.right: parent.right
                     anchors.rightMargin: Style.space(4)
                     anchors.verticalCenter: parent.verticalCenter
                     text: Peek.fmtCell(root.detailPairs[detailRowItem.index] ? root.detailPairs[detailRowItem.index].value : null)
                     color: {
                       if (!root.detailPairs[detailRowItem.index]) return root.foreground
                       var v = root.detailPairs[detailRowItem.index].value
                       if (Peek.isNull(v)) return root.dim
                       return detailRowItem.index === root.selectedIndex ? root.selectedText : root.foreground
                     }
                     font.family: root.fontFamily
                     font.pixelSize: Style.font.bodySmall
                     font.italic: root.detailPairs[detailRowItem.index] ? Peek.isNull(root.detailPairs[detailRowItem.index].value) : false
                     elide: Text.ElideMiddle
                   }
                 }
               }
             }

             Item {
               id: listContainer
               anchors.fill: parent
              visible: root.view !== "rows" && root.view !== "form"

              Text {
                visible: root.items.length === 0
                anchors.centerIn: parent
                text: root.emptyText()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                horizontalAlignment: Text.AlignHCenter
              }
              ListView {
                id: list
                anchors.fill: parent
                visible: root.items.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.items.length
                CC.ScrollBar.vertical: CC.ScrollBar {
                  policy: list.contentHeight > list.height ? CC.ScrollBar.AsNeeded : CC.ScrollBar.AlwaysOff
                }

                delegate: Rectangle {
                  id: listRow
                  required property int index
                  width: list.width
                  height: Math.max(Style.space(32), Style.font.body + Style.space(14))
                  color: index === root.selectedIndex ? root.selectedBackground : "transparent"

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onContainsMouseChanged: if (containsMouse) root.selectedIndex = listRow.index
                    onClicked: root.activate()
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items[listRow.index] ? root.items[listRow.index].label : ""
                    color: listRow.index === root.selectedIndex ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideMiddle
                    width: Math.min(parent.width * 0.45, implicitWidth + Style.space(2))
                  }

                   Text {
                     textFormat: Text.PlainText
                     anchors.right: parent.right
                     anchors.rightMargin: Style.space(4)
                     anchors.verticalCenter: parent.verticalCenter
                     text: root.items[listRow.index] ? root.items[listRow.index].sub : ""
                     color: root.dim
                     font.family: root.fontFamily
                     font.pixelSize: Style.font.caption
                     elide: Text.ElideMiddle
                     width: Math.min(parent.width * 0.55, implicitWidth + Style.space(2))
                   }
                 }
               }
             }

             Column {
               id: formContainer
               visible: root.view === "form"
               anchors.horizontalCenter: parent.horizontalCenter
               anchors.top: parent.top
               anchors.topMargin: Math.max(Style.space(10), (parent.height - formColumnHeight) / 3)
               spacing: Style.space(5)
               width: Math.min(parent.width - Style.space(20), Style.space(420))

               readonly property real formColumnHeight: childrenRect.height

               TextField {
                 id: nameField
                 width: parent.width
                 foreground: root.foreground
                 placeholderText: "Name *"
                 onAccepted: hostField.forceActiveFocus()
                 KeyNavigation.down: hostField
                 KeyNavigation.up: databaseField
               }

               TextField {
                 id: hostField
                 width: parent.width
                 foreground: root.foreground
                 placeholderText: "Host *  e.g. 127.0.0.1"
                 onAccepted: portField.forceActiveFocus()
                 KeyNavigation.down: portField
                 KeyNavigation.up: nameField
               }

               TextField {
                 id: portField
                 width: parent.width
                 foreground: root.foreground
                 placeholderText: "Port (3306)"
                 onAccepted: userField.forceActiveFocus()
                 KeyNavigation.down: userField
                 KeyNavigation.up: hostField
               }

               TextField {
                 id: userField
                 width: parent.width
                 foreground: root.foreground
                 placeholderText: "User"
                 onAccepted: passwordField.forceActiveFocus()
                 KeyNavigation.down: passwordField
                 KeyNavigation.up: portField
               }

               TextField {
                 id: passwordField
                 width: parent.width
                 foreground: root.foreground
                 password: true
                 placeholderText: "Password"
                 onAccepted: databaseField.forceActiveFocus()
                 KeyNavigation.down: databaseField
                 KeyNavigation.up: userField
               }

               TextField {
                 id: databaseField
                 width: parent.width
                 foreground: root.foreground
                 placeholderText: "Default database (optional — ⏎ saves)"
                 onAccepted: root.saveForm()
                 KeyNavigation.up: passwordField
                 KeyNavigation.down: nameField
               }
              }
            }

          Item {
            id: footer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.view === "rows" ? pageRow.implicitHeight : hintRow.implicitHeight

            RowLayout {
              id: pageRow
              visible: root.view === "rows"
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: root.isQueryResult
                  ? Peek.rangeLabel(root.offset, root.shown, root.tableTotal, root.truncated) + (root.lastSql !== "" ? "  ·  " + root.lastSql : "")
                  : Peek.rangeLabel(root.offset, root.shown, root.tableTotal, root.truncated)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
                Layout.fillWidth: true
              }

              Button {
                text: "◀ Prev"
                enabled: !root.isQueryResult && root.offset > 0 && !root.busy
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.prevPage()
              }

              Button {
                text: "Next ▶"
                enabled: !root.isQueryResult && (root.offset + root.shown < root.tableTotal) && !root.busy
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.nextPage()
              }
            }

            Text {
              id: hintRow
              visible: root.view !== "rows"
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.view === "form") {
                  if (root.errorText !== "") return root.errorText
                  return "⏎ next · last field saves · esc cancel"
                }
                if (root.view === "profiles") {
                  return root.activeFilter !== "" ? ("filter: " + root.activeFilter) : "n new · e edit · d delete · ⏎ open · esc back"
                }
                return root.activeFilter !== "" ? ("filter: " + root.activeFilter) : root.hintText
              }
              color: root.view === "form" && root.errorText !== "" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
            }
          }

          ConfirmDialog {
            id: deleteConfirm
            anchors.fill: parent
            z: 20
            opened: root.deleteConfirmOpen
            message: "Remove connection \"" + root.deleteName + "\"? Its stored password is deleted too."
            confirmText: "Remove"
            background: root.background
            foreground: root.foreground
            scrim: root.scrim
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
            cornerRadius: root.cornerRadius
            onCanceled: root.deleteConfirmOpen = false
            onConfirmed: {
              root.deleteConfirmOpen = false
              root.deleteSelected()
            }
          }
        }
      }
    }
  }
}
