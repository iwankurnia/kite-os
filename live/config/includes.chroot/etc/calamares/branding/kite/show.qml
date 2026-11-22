/* KiteOS installer slideshow (Calamares slideshow API 2). */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function onActivate() { }
    function onLeave() { }

    Timer {
        interval: 15000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Image {
            id: logo1
            source: "kite-logo.png"
            width: 128; height: 128
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 40
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: logo1.bottom
            anchors.topMargin: 24
            width: 560
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("<h2>Welcome to KiteOS</h2>" +
                  "A light Debian 13 desktop for your Chromebook.<br/>" +
                  "The installation runs by itself and takes about 10–15 minutes.")
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: 560
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("<h2>Feels like a Chromebook</h2>" +
                  "Tap the <b>Search</b> key to open the launcher.<br/>" +
                  "Search + top-row keys give F1–F10. Search + Backspace is Delete.")
        }
    }
    Slide {
        Text {
            anchors.centerIn: parent
            width: 560
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("<h2>Hibernation built in</h2>" +
                  "Close the lid to sleep; after an hour KiteOS hibernates, so a flat battery never loses your work.<br/>" +
                  "Use <b>Apps &amp; Storage</b> to keep apps and their data on a USB or SD disk.")
        }
    }
}
