// cctop - AI usage/cost monitor for the KDE panel.
// Panel shows the live Claude session usage; the popup shows the monthly
// cost per provider, live session/weekly limits and subscriptions.
// All data is read locally (no accounts, no API keys).
// Copyright (C) 2026 NventaTech — GPL-3.0-or-later
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ----------------- design tokens (graphite + petrol) -----------------
    property color bgColor: "#1a1a1d"
    property color surfaceColor: "#242427"
    property color surface2Color: "#2d2d31"
    property color borderColor: "#34343a"
    property color textColor: "#eaeaee"
    property color mutedColor: "#909299"
    property color accentColor: "#2a9fb8"
    property color okColor: "#4ade80"
    property color warnColor: "#fbbf24"
    property color alertColor: "#f2585f"

    // extra fixed subscriptions (name, price, currency) — auto-detected
    // Claude plan is prepended to this list
    property var extraSubscriptions: []

    // donation link (heart button in the header; hidden while empty)
    property string donateUrl: "https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD"

    // ----------------- i18n -----------------
    readonly property string lang: Plasmoid.configuration.language
    readonly property var strings: ({
        en: {
            loading: "loading…", month: "this month", today: "today",
            session: "CURRENT SESSION", weeklyAll: "ALL MODELS", weeklyModel: "MODEL",
            resets: "resets", inWord: "in", thisWindow: "this window",
            noSession: "no live data", subs: "SUBSCRIPTIONS", subsTotal: "Total",
            perMonth: "/mo", tipMonth: "this month", tipSession: "session",
            hist: "RECENT SESSIONS"
        },
        pt_BR: {
            loading: "carregando…", month: "este mês", today: "hoje",
            session: "SESSÃO ATUAL", weeklyAll: "TODOS OS MODELOS", weeklyModel: "MODELO",
            resets: "reseta", inWord: "em", thisWindow: "nesta janela",
            noSession: "sem dados ao vivo", subs: "ASSINATURAS", subsTotal: "Total",
            perMonth: "/mês", tipMonth: "neste mês", tipSession: "sessão",
            hist: "SESSÕES RECENTES"
        },
        es: {
            loading: "cargando…", month: "este mes", today: "hoy",
            session: "SESIÓN ACTUAL", weeklyAll: "TODOS LOS MODELOS", weeklyModel: "MODELO",
            resets: "se reinicia", inWord: "en", thisWindow: "en esta ventana",
            noSession: "sin datos en vivo", subs: "SUSCRIPCIONES", subsTotal: "Total",
            perMonth: "/mes", tipMonth: "en este mes", tipSession: "sesión",
            hist: "SESIONES RECIENTES"
        }
    })
    readonly property var localeNames: ({ en: "en_US", pt_BR: "pt_BR", es: "es_ES" })
    function tr(key) { return (strings[lang] || strings.en)[key] }

    // ----------------- state -----------------
    property var providers: []
    property real costMonth: 0
    property real costToday: 0
    property var block: null
    property var live: null
    property var subscription: null
    property var sessionModels: []
    property var history: []
    property var spark: []
    property bool showHistory: false
    property bool liveStale: false
    property bool notified: false
    property bool loaded: false
    property double now: Date.now()

    property string fetchScript: Qt.resolvedUrl("../code/fetch.sh").toString().replace("file://", "")

    // ----------------- helpers -----------------
    function money(v) { return "$" + v.toFixed(v >= 100 ? 0 : 2) }

    // green (0%) → yellow (~50%) → red (100%), like the Claude Code usage bar
    function sevColor(pct) {
        var t = Math.max(0, Math.min(1, pct / 100))
        return Qt.hsla((1 - t) * 0.33, 0.72, 0.58, 1)
    }

    // "claude-fable-5" -> "Fable 5", "claude-haiku-4-5-20251001" -> "Haiku 4.5"
    function prettyModel(m) {
        var p = m.replace("claude-", "").split("-")
        if (p.length && /^\d{8}$/.test(p[p.length - 1])) p.pop()
        return p.map(function(s) { return s.charAt(0).toUpperCase() + s.slice(1) })
                .join(" ").replace(/(\d) (\d)/, "$1.$2")
    }

    // main model of a session (background haiku calls filtered out)
    function mainModel(list) {
        list = list || []
        var main = list.filter(function(m) { return m.indexOf("haiku") < 0 })
        var pick = main.length ? main : list
        return pick.length ? prettyModel(pick[0]) : ""
    }
    function sessionModel() { return mainModel(sessionModels) }

    // "1h 30m" until an ISO timestamp
    function timeLeft(iso) {
        var mins = Math.max(0, Math.round((new Date(iso).getTime() - now) / 60000))
        var h = Math.floor(mins / 60), m = mins % 60
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    function allSubscriptions() {
        var list = []
        if (subscription) list.push(subscription)
        return list.concat(extraSubscriptions)
    }

    function subsTotal() {
        var t = 0, list = allSubscriptions()
        for (var i = 0; i < list.length; i++) t += list[i].price
        return t
    }

    // panel label follows the configured display mode
    function compactText() {
        var mode = Plasmoid.configuration.panelDisplay
        if (mode === "today") return money(costToday)
        if (mode === "subs") return (subscription ? subscription.currency : "US$") + subsTotal()
        return live ? live.session.pct + "%" : (block ? money(block.costUSD) : "cc")
    }

    // one desktop notification per 5h window when crossing the threshold
    function checkNotify() {
        var th = Plasmoid.configuration.notifyThreshold
        if (th <= 0 || !live || liveStale) return
        if (live.session.pct < th) { notified = false; return }
        if (notified) return
        notified = true
        var msg = "Claude " + live.session.pct + "% · " + tr("resets") + " "
                + Qt.formatTime(new Date(live.session.resets_at), "HH:mm")
        notifier.connectSource("notify-send -a cctop -i office-chart-bar cctop \"" + msg + "\"")
    }

    // ===================== DATA =====================
    P5Support.DataSource {
        id: fetcher
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
            try {
                var j = JSON.parse(data.stdout)
                root.providers = j.providers || []
                root.costMonth = j.totalMonth || 0
                root.costToday = j.totalToday || 0
                root.block = j.block
                // token expired = live comes back null: keep showing the last
                // known limits (marked stale) instead of dropping the cards
                if (j.live) {
                    root.live = j.live
                    root.liveStale = false
                } else if (root.live) {
                    root.liveStale = true
                }
                root.subscription = j.subscription
                root.sessionModels = j.sessionModels || []
                root.history = j.history || []
                root.spark = j.spark || []
                root.loaded = true
                root.checkNotify()
            } catch (e) { /* keep last values */ }
        }
    }

    P5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: function(source) { disconnectSource(source) }
    }

    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            root.now = Date.now()
            fetcher.connectSource("bash " + root.fetchScript)
        }
    }

    toolTipMainText: "cctop"
    toolTipSubText: loaded
        ? money(costMonth) + " " + tr("tipMonth")
          + (live ? " · " + tr("tipSession") + " " + live.session.pct + "%" : "")
        : tr("loading")

    preferredRepresentation: compactRepresentation

    // ===================== PANEL =====================
    compactRepresentation: MouseArea {
        Layout.preferredWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 4
        Layout.minimumWidth: Layout.preferredWidth
        onClicked: root.expanded = !root.expanded
        PC3.Label {
            id: label
            anchors.centerIn: parent
            text: root.compactText()
            font.family: "monospace"
            font.bold: true
            color: Plasmoid.configuration.panelDisplay === "session" && root.live
                ? root.sevColor(root.live.session.pct) : Kirigami.Theme.textColor
        }
    }

    // ===================== POPUP =====================
    fullRepresentation: Item {
        id: fullRep
        Layout.preferredWidth: Kirigami.Units.gridUnit * 23
        Layout.preferredHeight: column.implicitHeight + Kirigami.Units.gridUnit * 2
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight

        readonly property int microSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 0.9)
        readonly property int smallSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.0)

        Rectangle { anchors.fill: parent; color: root.bgColor }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit
            spacing: Math.round(Kirigami.Units.gridUnit * 0.55)

            // ---------- header ----------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing * 2
                PC3.Label {
                    text: "cctop"
                    font.bold: true
                    color: root.textColor
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.15)
                }
                PC3.Label {
                    text: new Date(root.now).toLocaleDateString(Qt.locale(root.localeNames[root.lang] || "en_US"), "dddd, d MMMM")
                    color: root.mutedColor
                    font.pixelSize: fullRep.microSize
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                }
                PC3.ToolButton {
                    icon.name: "love"
                    visible: root.donateUrl !== ""
                    onClicked: Qt.openUrlExternally(root.donateUrl)
                }
                PC3.ToolButton {
                    icon.name: "view-history"
                    checkable: true
                    checked: root.showHistory
                    onClicked: root.showHistory = !root.showHistory
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: fetcher.connectSource("bash " + root.fetchScript)
                }
                PC3.ToolButton {
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }

            // ---------- hero: monthly total ----------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    text: root.loaded ? root.money(root.costMonth) : "…"
                    color: root.textColor
                    font.pixelSize: Kirigami.Units.gridUnit * 2.4
                    font.bold: true
                }
                PC3.Label {
                    text: root.tr("month") + "  ·  " + root.tr("today") + " " + root.money(root.costToday)
                    color: root.mutedColor
                    font.pixelSize: fullRep.smallSize
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    height: 6
                    radius: 3
                    clip: true
                    color: root.surface2Color
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: root.providers
                            Rectangle {
                                height: parent.height
                                width: root.costMonth > 0 ? parent.width * (modelData.costMonth / root.costMonth) : 0
                                color: modelData.color
                            }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing * 3
                    Repeater {
                        model: root.providers
                        Row {
                            spacing: Kirigami.Units.smallSpacing
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: modelData.color
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            PC3.Label {
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: fullRep.microSize
                                opacity: 0.9
                            }
                            PC3.Label {
                                text: root.money(modelData.costMonth)
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                        }
                    }
                }

                // last 7 days (bars scale to the week's peak, today highlighted)
                Item {
                    id: sparkBox
                    Layout.fillWidth: true
                    Layout.topMargin: Kirigami.Units.smallSpacing * 2
                    visible: root.spark.length > 0
                    implicitHeight: Kirigami.Units.gridUnit * 3.2
                    property real peak: Math.max.apply(null, root.spark.map(function(s) { return s.c }).concat([0.01]))

                    RowLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing
                        Repeater {
                            model: root.spark
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: Math.max(3, parent.height * (modelData.c / sparkBox.peak))
                                        radius: 2
                                        color: root.accentColor
                                        opacity: index === root.spark.length - 1 ? 1 : 0.5
                                    }
                                }
                                PC3.Label {
                                    text: new Date(modelData.d + "T12:00:00").toLocaleDateString(Qt.locale(root.localeNames[root.lang] || "en_US"), "ddd").slice(0, 3)
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }

            // ---------- current session (live 5h limit) ----------
            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: sessionCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: sessionCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 2

                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: root.tr("session")
                            color: root.mutedColor
                            font.pixelSize: fullRep.microSize
                            font.letterSpacing: 0.5
                        }
                        PC3.Label {
                            text: root.sessionModel()
                            visible: text !== ""
                            color: root.accentColor
                            font.bold: true
                            font.pixelSize: fullRep.microSize
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        PC3.Label {
                            text: root.live ? root.live.session.pct + "%" : "—"
                            font.bold: true
                            font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.45)
                            color: root.live ? root.sevColor(root.live.session.pct) : root.mutedColor
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 6
                        radius: 3
                        color: root.surface2Color
                        Rectangle {
                            width: parent.width * (root.live ? root.live.session.pct / 100 : 0)
                            height: parent.height
                            radius: 3
                            color: root.live ? root.sevColor(root.live.session.pct) : root.mutedColor
                        }
                    }

                    PC3.Label {
                        Layout.fillWidth: true
                        visible: root.live !== null
                        text: root.live
                            ? root.tr("resets") + " " + Qt.formatTime(new Date(root.live.session.resets_at), "HH:mm")
                              + " (" + root.tr("inWord") + " " + root.timeLeft(root.live.session.resets_at) + ")"
                              + (root.block ? "  ·  " + root.money(root.block.costUSD) + " " + root.tr("thisWindow") : "")
                              + (root.liveStale ? "  ·  offline" : "")
                            : ""
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        wrapMode: Text.WordWrap
                    }
                    PC3.Label {
                        visible: root.live === null && root.loaded
                        text: root.tr("noSession")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                    }
                }
            }

            // ---------- recent sessions (toggled by the history button) ----------
            Rectangle {
                Layout.fillWidth: true
                visible: root.showHistory && root.history.length > 0
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: histCol.implicitHeight + Kirigami.Units.gridUnit * 1.6

                ColumnLayout {
                    id: histCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("hist")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.history
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: new Date(modelData.last).toLocaleString(Qt.locale(root.localeNames[root.lang] || "en_US"), "d MMM HH:mm")
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                            PC3.Label {
                                text: root.mainModel(modelData.models)
                                color: root.accentColor
                                font.bold: true
                                font.pixelSize: fullRep.microSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: root.money(modelData.cost)
                                color: root.textColor
                                font.pixelSize: fullRep.microSize
                            }
                        }
                    }
                }
            }

            // ---------- weekly limits (live) ----------
            RowLayout {
                Layout.fillWidth: true
                visible: root.live !== null
                spacing: Kirigami.Units.smallSpacing * 2

                Repeater {
                    model: root.live ? [
                        { label: root.tr("weeklyAll"), data: root.live.weekly },
                        { label: (root.sessionModel() || root.tr("weeklyModel")).toUpperCase(), data: root.live.weekly_model }
                    ].filter(e => e.data) : []

                    Rectangle {
                        Layout.fillWidth: true
                        radius: 12
                        color: root.surfaceColor
                        border.color: root.borderColor
                        border.width: 1
                        implicitHeight: weeklyCol.implicitHeight + Kirigami.Units.gridUnit

                        ColumnLayout {
                            id: weeklyCol
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.gridUnit * 0.65
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                PC3.Label {
                                    text: modelData.label
                                    color: root.mutedColor
                                    font.pixelSize: fullRep.microSize
                                    font.letterSpacing: 0.5
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                PC3.Label {
                                    text: modelData.data.pct + "%"
                                    font.bold: true
                                    color: root.sevColor(modelData.data.pct)
                                    font.pixelSize: fullRep.smallSize
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 6
                                radius: 3
                                color: root.surface2Color
                                Rectangle {
                                    width: parent.width * modelData.data.pct / 100
                                    height: parent.height
                                    radius: 3
                                    color: root.sevColor(modelData.data.pct)
                                }
                            }
                            PC3.Label {
                                text: root.tr("resets") + " " + new Date(modelData.data.resets_at).toLocaleString(Qt.locale(root.localeNames[root.lang] || "en_US"), "ddd HH:mm")
                                color: root.mutedColor
                                font.pixelSize: fullRep.microSize
                            }
                        }
                    }
                }
            }

            // ---------- subscriptions ----------
            Rectangle {
                Layout.fillWidth: true
                visible: root.allSubscriptions().length > 0
                radius: 12
                color: root.surfaceColor
                border.color: root.borderColor
                border.width: 1
                implicitHeight: subsCol.implicitHeight + Kirigami.Units.gridUnit * 1.2

                ColumnLayout {
                    id: subsCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.65
                    spacing: Kirigami.Units.smallSpacing * 1.5

                    PC3.Label {
                        text: root.tr("subs")
                        color: root.mutedColor
                        font.pixelSize: fullRep.microSize
                        font.letterSpacing: 0.5
                    }
                    Repeater {
                        model: root.allSubscriptions()
                        RowLayout {
                            Layout.fillWidth: true
                            PC3.Label {
                                text: modelData.name
                                color: root.textColor
                                font.pixelSize: fullRep.smallSize
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            PC3.Label {
                                text: modelData.currency + modelData.price + root.tr("perMonth")
                                color: root.mutedColor
                                font.pixelSize: fullRep.smallSize
                            }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: root.borderColor }
                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: root.tr("subsTotal")
                            font.bold: true
                            color: root.textColor
                            font.pixelSize: fullRep.smallSize
                            Layout.fillWidth: true
                        }
                        PC3.Label {
                            text: (root.subscription ? root.subscription.currency : "US$") + root.subsTotal() + root.tr("perMonth")
                            font.bold: true
                            color: root.accentColor
                            font.pixelSize: fullRep.smallSize
                        }
                    }
                }
            }

            // any surplus height goes below the cards, never between them
            // (e.g. when the dialog is restored bigger than the content)
            Item { Layout.fillHeight: true }
        }
    }
}
