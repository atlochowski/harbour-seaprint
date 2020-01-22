import QtQuick 2.0
import Sailfish.Silica 1.0
import Sailfish.Pickers 1.0
import seaprint.ippdiscovery 1.0
import seaprint.ippprinter 1.0
import "utils.js" as Utils
import "../components"
import Nemo.DBus 2.0

Page {
    id: page
    allowedOrientations: Orientation.All

    property string selectedFile: ""
    property string selectedFileType

    WifiChecker {
        id: wifi
        onConnectedChanged: {
            console.log("conn", connected, ssid)
            if(connected) {
                var favourites = db.getFavourites(ssid);
                console.log(favourites);
                IppDiscovery.favourites = favourites;
            }
            else {
                IppDiscovery.favourites = []
            }

        }

        property bool initialSSIDchange: true

        onSsidChanged: {
            console.log("ssid changed", ssid);
            if(!initialSSIDchange)
            {
                IppDiscovery.reset();
            }
            initialSSIDchange = false;
        }
    }

    signal refreshed()

    Component.onCompleted: {
        IppDiscovery.discover();
        if(selectedFile != "")
        {  // Until i can convince FilePickerPage to do its magic without user interaction
            if(Utils.endsWith(".pdf", selectedFile))
            {
                selectedFileType = "application/pdf"
            }
            else if(Utils.endsWith(".jpg", selectedFile) || Utils.endsWith(".jpeg", selectedFile))
            {
                selectedFileType = "image/jpeg"
            }
            else
            {
                selectedFile = ""
            }
        }
    }

    // To enable PullDownMenu, place our content in a SilicaFlickable
    SilicaFlickable {
        anchors.fill: parent

        // PullDownMenu and PushUpMenu must be declared in SilicaFlickable, SilicaListView or SilicaGridView
        PullDownMenu {
            MenuItem {
                text: qsTr("About SeaPrint")
                onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml"))
                }
            MenuItem {
                text: qsTr("Add by URL")
                enabled: wifi.connected
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("AddPrinterDialog.qml"),
                                                {ssid: wifi.ssid, title: qsTr("URL")});
                        dialog.accepted.connect(function() {
                            console.log("add", wifi.ssid, dialog.value);
                            db.addFavourite(wifi.ssid, dialog.value);
                            IppDiscovery.favourites = db.getFavourites(wifi.ssid);
                    })
                }
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: {
                    IppDiscovery.discover();
                    page.refreshed();
                }
            }
        }

        SilicaListView {
            anchors.fill: parent
            id: listView
            model: IppDiscovery
            spacing: Theme.paddingSmall


            delegate: ListItem {
                id: delegate
                contentItem.height: visible ? Math.max(column.implicitHeight, Theme.itemSizeLarge+2*Theme.paddingMedium) : 0

                visible: false

                property string name: printer.attrs["printer-name"].value != "" ? printer.attrs["printer-name"].value : qsTr("Unknown")
                // TODO: check  if conversion targets are supported if file is PDF
                property bool canPrint: printer.attrs["document-format-supported"].value.indexOf(selectedFileType) != -1 || selectedFileType == "application/pdf"

                Connections {
                    target: printer
                    onAttrsChanged: {
                        if(Object.keys(printer.attrs).length === 0) {
                            delegate.visible = false
                        }
                        else {
                            delegate.visible = true
                        }
                    }
                }


                Connections {
                    target: page
                    onRefreshed: {
                        console.log("onRefreshed")
                        printer.refresh()
                    }
                }

                onClicked: {
                    if(!canPrint)
                        return;
                    if(selectedFile != "")
                    {
                        pageStack.push(Qt.resolvedUrl("PrinterPage.qml"), {printer: printer, selectedFile: selectedFile})
                    }
                    else
                    {
                        notifier.notify(qsTr("No file selected"))
                    }
                }

                IppPrinter {
                    id: printer
                    url: model.display
                }

                Image {
                    id: icon
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.topMargin: Theme.paddingMedium
                    anchors.leftMargin: Theme.paddingMedium

                    height: Theme.itemSizeLarge
                    width: Theme.itemSizeLarge
                    source: printer.attrs["printer-icons"] ? "image://ippdiscovery/"+printer.attrs["printer-icons"].value[0] : "icon-seaprint-nobg.svg"
                    // Some printers serve their icons over https with invalid certs...
                    onStatusChanged: if (status == Image.Error) source = "icon-seaprint-nobg.svg"
                }

                Column {
                    id: column
                    anchors.left: icon.right
                    anchors.leftMargin: Theme.paddingMedium

                    Label {
                        id: name_label
                        color: canPrint ? Theme.primaryColor : Theme.secondaryColor
                        text: name
                    }

                    Label {
                        id: mm_label
                        color: canPrint ? Theme.primaryColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: printer.attrs["printer-make-and-model"].value
                    }

                    Label {
                        id: uri_label
                        color: canPrint ? Theme.highlightColor : Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeTiny
                        text: printer.url
                    }

                    Label {
                        id: format_label
                        color: canPrint ? Theme.primaryColor : "red"
                        font.pixelSize: Theme.fontSizeExtraSmall
                        text: Utils.supported_formats(printer)
                    }
                }

                RemorseItem {
                    id: removeRemorse
                }

                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("View jobs")
                        onClicked:  pageStack.push(Qt.resolvedUrl("JobsPage.qml"), {printer: printer})
                    }
                    MenuItem {
                        text: qsTr("Remove printer")
                        visible: db.isFavourite(wifi.ssid, model.display)
                        onClicked: {
                            removeRemorse.execute(delegate, qsTr("Removing printer"),
                                                  function() {db.removeFavourite(wifi.ssid, model.display);
                                                              IppDiscovery.favourites = db.getFavourites()})
                        }
                    }
                }

            }
            onCountChanged: {
                console.log("count", count)
            }
        }
    }
    DockedPanel {
        id: fileDock
        open: true
        height: fileButton.height*2
        width: parent.width
        dock: Dock.Bottom

        ValueButton {
            id: fileButton
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            label: qsTr("Choose file")
            value: selectedFile != "" ? selectedFile : qsTr("None")
            onClicked: pageStack.push(filePickerPage)
        }
        Component {
            id: filePickerPage
            FilePickerPage {
                title: fileButton.label
                showSystemFiles: false
                nameFilters: ["*.pdf", "*.jpg", "*.jpeg", "*.pwg", "*.urf"]

                onSelectedContentPropertiesChanged: {
                    page.selectedFile = selectedContentProperties.filePath
                    page.selectedFileType = selectedContentProperties.mimeType
                }
            }
        }
    }
}
