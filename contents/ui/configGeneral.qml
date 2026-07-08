// cctop - settings page (language, panel display, notifications, donate).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_language
    property string cfg_panelDisplay
    property int cfg_notifyThreshold
    property int cfg_refreshInterval
    property int cfg_budgetMonthly
    property string cfg_extraSubscriptions

    // defaults mirrored from config/main.xml (silences plasmashell warnings)
    property string cfg_languageDefault: "en"
    property string cfg_panelDisplayDefault: "session"
    property int cfg_notifyThresholdDefault: 85
    property int cfg_refreshIntervalDefault: 60
    property int cfg_budgetMonthlyDefault: 0
    property string cfg_extraSubscriptionsDefault: "[]"

    // working copy of the subscription list (saved back as JSON)
    property var subsList: []
    Component.onCompleted: {
        try { subsList = JSON.parse(cfg_extraSubscriptions) } catch (e) { subsList = [] }
    }
    function saveSubs() {
        subsList = subsList.slice()
        cfg_extraSubscriptions = JSON.stringify(subsList)
    }

    readonly property string donateUrl: "https://www.paypal.com/donate/?business=SR28XBBCYSPHE&no_recurring=0&item_name=Help+me+buy+a+coffee.&currency_code=USD"

    // breathing room above the first row
    Item { implicitHeight: Kirigami.Units.largeSpacing * 2 }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Language:"
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "en", text: "English" },
            { value: "pt_BR", text: "Português (Brasil)" },
            { value: "es", text: "Español" }
        ]
        onActivated: page.cfg_language = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_language)
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Panel shows:"
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "session", text: "Session %" },
            { value: "today", text: "Spend today" },
            { value: "subs", text: "Subscriptions total" }
        ]
        onActivated: page.cfg_panelDisplay = currentValue
        Component.onCompleted: currentIndex = indexOfValue(page.cfg_panelDisplay)
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Notify at session % (0 = off):"
        from: 0
        to: 100
        stepSize: 5
        value: page.cfg_notifyThreshold
        onValueModified: page.cfg_notifyThreshold = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Monthly budget in US$ (0 = off):"
        from: 0
        to: 100000
        stepSize: 10
        value: page.cfg_budgetMonthly
        onValueModified: page.cfg_budgetMonthly = value
    }

    QQC2.SpinBox {
        Kirigami.FormData.label: "Refresh every (seconds):"
        from: 30
        to: 3600
        stepSize: 30
        value: page.cfg_refreshInterval
        onValueModified: page.cfg_refreshInterval = value
    }

    Kirigami.Separator { Kirigami.FormData.isSection: true }

    // fixed AI subscriptions besides the auto-detected Claude plan
    ColumnLayout {
        Kirigami.FormData.label: "Other AI subscriptions:"
        Kirigami.FormData.buddyFor: presetBox
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: page.subsList
            RowLayout {
                spacing: Kirigami.Units.smallSpacing * 2
                QQC2.Label {
                    text: modelData.name
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 9
                }
                QQC2.Label { text: "US$" + modelData.price + "/mo"; opacity: 0.7 }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: { page.subsList.splice(index, 1); page.saveSubs() }
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.ComboBox {
                id: presetBox
                textRole: "text"
                model: [
                    { text: "ChatGPT Plus", name: "ChatGPT Plus", price: 20 },
                    { text: "ChatGPT Pro", name: "ChatGPT Pro", price: 200 },
                    { text: "GitHub Copilot Pro", name: "GitHub Copilot Pro", price: 10 },
                    { text: "Google AI Pro", name: "Google AI Pro", price: 20 },
                    { text: "Custom…", name: "", price: 0 }
                ]
                onActivated: {
                    nameField.text = model[currentIndex].name
                    priceField.value = model[currentIndex].price
                }
                Component.onCompleted: {
                    nameField.text = model[0].name
                    priceField.value = model[0].price
                }
            }
            QQC2.TextField {
                id: nameField
                placeholderText: "Name"
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            }
            QQC2.SpinBox { id: priceField; from: 0; to: 10000 }
            QQC2.Button {
                icon.name: "list-add"
                enabled: nameField.text !== ""
                onClicked: {
                    page.subsList.push({ name: nameField.text, price: priceField.value })
                    page.saveSubs()
                }
            }
        }
    }

    Kirigami.Separator { Kirigami.FormData.isSection: true }

    QQC2.Button {
        Kirigami.FormData.label: "Enjoying cctop?"
        text: "Donate via PayPal ❤"
        icon.name: "love"
        onClicked: Qt.openUrlExternally(page.donateUrl)
    }

    Image {
        Kirigami.FormData.label: " "
        source: Qt.resolvedUrl("../images/donate-qr.png")
        sourceSize.width: 140
        sourceSize.height: 140
        fillMode: Image.PreserveAspectFit
    }
}
