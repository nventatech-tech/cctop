// cctop - settings page (language, panel display, notifications).
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_language
    property string cfg_panelDisplay
    property int cfg_notifyThreshold

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
}
