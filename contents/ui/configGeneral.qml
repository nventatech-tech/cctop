// cctop - settings page (language, panel display, notifications, donate).
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_language
    property string cfg_panelDisplay
    property int cfg_notifyThreshold

    // defaults mirrored from config/main.xml (silences plasmashell warnings)
    property string cfg_languageDefault: "en"
    property string cfg_panelDisplayDefault: "session"
    property int cfg_notifyThresholdDefault: 85

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
