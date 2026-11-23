/* KiteOS installer slideshow — same structure as Debian 13's own
 * (calamares-settings-debian), which is known to render in this Calamares. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 15000
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: logo1
            source: "kite-logo.png"
            width: 128; height: 128
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -60
        }
        Text {
            anchors.horizontalCenter: logo1.horizontalCenter
            anchors.top: logo1.bottom
            anchors.topMargin: 24
            text: qsTr("<h2>Welcome to KiteOS</h2>" +
                  "A light Debian 13 desktop for your Chromebook.<br/>" +
                  "The installation runs by itself and takes about 10–15 minutes.")
            wrapMode: Text.WordWrap
            width: 560
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            text: qsTr("<h2>Feels like a Chromebook</h2>" +
                  "Tap the <b>Search</b> key to open the launcher.<br/>" +
                  "Search + top-row keys give F1–F10. Search + Backspace is Delete.")
            wrapMode: Text.WordWrap
            width: 560
            horizontalAlignment: Text.AlignHCenter
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            text: qsTr("<h2>Hibernation built in</h2>" +
                  "Close the lid to sleep; after an hour KiteOS hibernates, so a flat battery never loses your work.<br/>" +
                  "Use <b>App Centre</b> to keep apps and their data on a USB or SD disk.")
            wrapMode: Text.WordWrap
            width: 560
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
