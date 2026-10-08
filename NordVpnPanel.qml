pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.DCommon.Widgets as D
import "locationLookup.js" as Geo
import "." as Nord

Item {
    id: root
    property var pluginService: null
    property bool compact: false
    property bool panelLive: visible
    property bool activated: false
    property bool initialized: false
    property string country: ""
    property string city: ""
    property string region: ""
    property string group: ""
    property var favorites: []
    readonly property var vpn: Nord.NordVpnService
    readonly property var store: pluginService || PluginService
    readonly property var currentCities: vpn.cityCatalogs[country] || []
    readonly property var regionOptions: Geo.regions(country, currentCities)
    readonly property var filteredCities: region ? Geo.regionCities(country, region, currentCities) : currentCities
    readonly property string destination: country ? country.replace(/_/g, " ") + (city ? " · " + city.replace(/_/g, " ") : region ? " · " + region : " · Fastest server") : "Fastest available server"
    property alias mapView: worldMap
    property alias tabIndex: tabs.currentIndex
    clip: true

    function loadFavorites() { favorites = store.loadPluginData("nordVpnControl", "favorites", []); }
    function toggleFavorite(value) {
        favorites = favorites.indexOf(value) >= 0 ? favorites.filter(x => x !== value) : favorites.concat([value]);
        store.savePluginData("nordVpnControl", "favorites", favorites);
    }
    function selectCountry(value, focusMap) {
        country = value; city = ""; region = "";
        if (value) vpn.fetchCities(value);
        if (focusMap === true) worldMap.focusCountry();
        else if (!value) worldMap.resetView();
    }
    function selectRegion(value) {
        region = value;
        const choices = Geo.regionCities(country, value, currentCities);
        city = value && choices.length === 1 ? choices[0] : "";
    }
    function selectCity(value) {
        if (value && currentCities.indexOf(value) < 0) return;
        city = value;
        const point = Geo.cityMarkers(country, currentCities).find(p => p.city === value);
        region = Geo.countryKey(country) === "unitedstates" && point ? point.region : "";
    }
    function connectCountryFromMap(value) {
        if (vpn.busy || !vpn.ready) return;
        selectCountry(value); group = "";
        vpn.connectTo(value, "", "");
    }
    function connectCityFromMap(value, targetCity) {
        if (vpn.busy || !vpn.ready || (vpn.cityCatalogs[value] || []).indexOf(targetCity) < 0) return;
        if (country !== value) selectCountry(value);
        selectCity(targetCity); group = "";
        vpn.connectTo(value, targetCity, "");
    }
    function syncActivity() {
        if (!initialized || panelLive === activated) return;
        activated = panelLive; vpn.setPanelActive(activated);
    }
    function connectSelection() { if (!region || city) vpn.connectTo(country, city, group); }
    Component.onCompleted: { vpn.initializeCache(store); vpn.retain(); initialized = true; loadFavorites(); vpn.prioritizeCountries(favorites); syncActivity(); }
    Component.onDestruction: { if (activated) vpn.setPanelActive(false); vpn.release(); }
    onPanelLiveChanged: syncActivity()
    onCurrentCitiesChanged: {
        if (city && currentCities.indexOf(city) < 0) city = "";
        if (region && !city) selectRegion(region);
    }
    Connections { target: root.store; function onPluginDataChanged(id) { if (id === "nordVpnControl") root.loadFavorites(); } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        spacing: Theme.spacingS
        RowLayout {
            Layout.fillWidth: true
            D.DIcon { name: "vpn_lock"; color: Theme.primary; size: Theme.iconSize }
            D.StyledText { objectName: "panelTitle"; text: "NordVPN"; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeXLarge; font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
            D.DIconButton { iconName: "refresh"; tooltipText: "Refresh status"; Accessible.name: "Refresh status"; enabled: !root.vpn.busy; onClicked: root.vpn.refresh(true) }
        }
        D.DCard {
            id: statusCard
            objectName: "statusCard"
            Layout.fillWidth: true
            Layout.preferredHeight: statusContent.implicitHeight + pad * 2
            tone: root.vpn.connected ? "primary" : ""
            RowLayout {
                id: statusContent
                anchors.fill: parent
                spacing: Theme.spacingM
                D.DIcon { objectName: "statusIcon"; name: root.vpn.connected ? "verified_user" : "vpn_lock"; size: Theme.iconSizeLarge; color: statusCard.accentColor }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXXS
                    D.StyledText { objectName: "statusTitle"; text: root.vpn.stateLabel; color: statusCard.contentColor; font.pixelSize: Theme.fontSizeLarge; font.weight: Theme.fontWeightMedium; Layout.fillWidth: true }
                    D.StyledText {
                        objectName: "statusDetails"
                        Layout.fillWidth: true; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall
                        text: root.vpn.connected ? [root.vpn.status.country, root.vpn.status.city, root.vpn.status.technology].filter(Boolean).join(" · ") : root.vpn.settings.killswitch === true ? "Kill Switch is on · Disconnected traffic may be blocked" : "Choose a location or use the fastest server"
                        color: statusCard.mutedColor
                    }
                }
            }
        }
        D.StyledText {
            Layout.fillWidth: true; visible: text.length > 0; font.pixelSize: Theme.fontSizeMedium
            text: root.vpn.errorMessage + (root.vpn.errorCode === "logged-out" ? "\nLog in from your desktop terminal with: nordvpn login" : "")
            color: Theme.error; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
        }
        D.DTabBar {
            id: tabs
            Layout.fillWidth: true
            showIcons: false
            model: [{text: "Map", icon: "public"}, {text: "Locations", icon: "location_on"}, {text: "Settings", icon: "settings"}]
            onTabClicked: index => currentIndex = index
        }
        StackLayout {
            currentIndex: tabs.currentIndex
            Layout.fillWidth: true; Layout.fillHeight: true
            ColumnLayout {
                spacing: Theme.spacingS
                RowLayout {
                    Layout.fillWidth: true
                    D.DDropdown {
                        Layout.fillWidth: true; Layout.preferredWidth: 240
                        options: ["Fastest server"].concat(root.vpn.countries.map(c => c.replace(/_/g, " ")))
                        currentValue: root.country ? root.country.replace(/_/g, " ") : "Fastest server"
                        enableFuzzySearch: true
                        onValueChanged: value => root.selectCountry(value === "Fastest server" ? "" : root.vpn.countries.find(c => c.replace(/_/g, " ") === value), true)
                    }
                    D.DDropdown {
                        visible: Geo.countryKey(root.country) === "unitedstates"
                        Layout.fillWidth: true; Layout.preferredWidth: 180
                        options: ["All states"].concat(root.regionOptions)
                        currentValue: root.region || "All states"
                        enabled: root.currentCities.length > 0
                        enableFuzzySearch: true
                        onValueChanged: value => { root.selectRegion(value === "All states" ? "" : value); if (root.region) worldMap.focusRegion(root.region); else worldMap.focusCountry(); }
                    }
                    D.DDropdown {
                        Layout.fillWidth: true; Layout.preferredWidth: 180
                        options: ["Any city"].concat(root.filteredCities.map(c => c.replace(/_/g, " ")))
                        currentValue: root.city ? root.city.replace(/_/g, " ") : "Any city"
                        enabled: !!root.country && root.filteredCities.length > 0
                        enableFuzzySearch: true
                        onValueChanged: value => root.selectCity(value === "Any city" ? "" : root.filteredCities.find(c => c.replace(/_/g, " ") === value))
                    }
                }
                WorldMap {
                    id: worldMap
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 110
                    availableCountries: root.vpn.countries
                    availableCities: root.currentCities
                    cityCatalogs: root.vpn.cityCatalogs
                    selectedCountry: root.country
                    selectedCity: root.city
                    selectedRegion: root.region
                    connectedCountry: root.vpn.connected ? root.vpn.status.country || "" : ""
                    connectedCity: root.vpn.connected ? root.vpn.status.city || "" : ""
                    onCountrySelected: country => root.connectCountryFromMap(country)
                    onCitySelected: (country, city) => root.connectCityFromMap(country, city)
                    onRegionSelected: (country, region) => { if (root.country !== country) root.selectCountry(country); root.selectRegion(region); }
                    onCitiesNeeded: country => root.vpn.ensureCities(country)
                }
                D.StyledText {
                    Layout.fillWidth: true
                    visible: !!root.region && root.filteredCities.length === 0
                    text: "No NordVPN cities listed in " + root.region + ". Choose another state or All states."
                    wrapMode: Text.WordWrap; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall
                }
                D.DCard {
                    id: destinationCard
                    objectName: "destinationCard"
                    Layout.fillWidth: true
                    Layout.preferredHeight: destinationContent.implicitHeight + pad * 2
                    ColumnLayout {
                        id: destinationContent
                        anchors.fill: parent
                        spacing: Theme.spacingS
                        RowLayout {
                            Layout.fillWidth: true
                            D.StyledText { objectName: "destinationLabel"; font.pixelSize: Theme.fontSizeMedium; text: root.destination; color: destinationCard.contentColor; font.weight: Theme.fontWeightMedium; Layout.fillWidth: true; elide: Text.ElideRight }
                            D.DIconButton { visible: !!root.country; iconName: root.favorites.indexOf(root.country) >= 0 ? "star" : "star_border"; tooltipText: "Favorite country"; Accessible.name: "Favorite country"; onClicked: root.toggleFavorite(root.country) }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            D.DButton {
                                objectName: "connectButton"
                                text: root.vpn.connected ? "Switch location" : root.vpn.status.state === "paused" ? "Resume VPN" : "Connect"
                                iconName: "vpn_lock"; busy: root.vpn.busy
                                enabled: root.vpn.ready && !root.vpn.busy && (!root.region || !!root.city)
                                Layout.fillWidth: true
                                onClicked: root.connectSelection()
                            }
                            D.DButton { text: "Disconnect"; enabled: root.vpn.connected && !root.vpn.busy; onClicked: root.vpn.disconnect() }
                            D.DButton { visible: root.vpn.hasCommand("pause") && !root.compact; text: "Pause 5 min"; enabled: root.vpn.connected && !root.vpn.busy; onClicked: root.vpn.pause("5m") }
                        }
                    }
                }
            }
            ColumnLayout {
                spacing: Theme.spacingS
                D.DTextField { id: search; objectName: "countrySearch"; Layout.fillWidth: true; placeholderText: "Search countries"; leftIconName: "search"; showClearButton: true }
                D.DListView {
                    id: countryList
                    objectName: "countryList"
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: Theme.spacingXS
                    Component.onCompleted: Controls.ScrollBar.vertical.objectName = "countryScrollbar"
                    model: root.vpn.countries.filter(c => c.replace(/_/g, " ").toLowerCase().indexOf(search.text.toLowerCase()) >= 0).sort((a, b) => (root.favorites.indexOf(b) >= 0 ? 1 : 0) - (root.favorites.indexOf(a) >= 0 ? 1 : 0) || a.localeCompare(b))
                    delegate: D.DCard {
                        id: countryCard
                        required property string modelData
                        objectName: "country:" + modelData
                        width: countryList.width
                        height: Math.max(Theme.listItemHeight, countryRow.implicitHeight + pad * 2)
                        pad: Theme.spacingS
                        tone: root.country === modelData ? "primary" : ""
                        clickable: true
                        Accessible.name: modelData.replace(/_/g, " ")
                        onClicked: root.selectCountry(modelData, true)
                        RowLayout {
                            id: countryRow
                            anchors.fill: parent
                            D.StyledText { text: countryCard.modelData.replace(/_/g, " "); color: countryCard.contentColor; font.pixelSize: Theme.fontSizeMedium; Layout.fillWidth: true; elide: Text.ElideRight }
                            D.DIconButton { iconName: root.favorites.indexOf(countryCard.modelData) >= 0 ? "star" : "star_border"; iconColor: countryCard.accentColor; Accessible.name: "Favorite " + countryCard.modelData.replace(/_/g, " "); onClicked: root.toggleFavorite(countryCard.modelData) }
                        }
                    }
                    D.StyledText { anchors.centerIn: parent; font.pixelSize: Theme.fontSizeMedium; visible: !countryList.count; text: root.vpn.ready ? "No matching countries" : "Locations load when NordVPN is available."; color: Theme.surfaceVariantText; width: parent.width; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter }
                }
                RowLayout {
                    Layout.fillWidth: true
                    D.DDropdown { Layout.fillWidth: true; options: ["Any city"].concat(root.currentCities.map(c => c.replace(/_/g, " "))); currentValue: root.city ? root.city.replace(/_/g, " ") : "Any city"; enabled: !!root.country; enableFuzzySearch: true; onValueChanged: value => root.selectCity(value === "Any city" ? "" : root.currentCities.find(c => c.replace(/_/g, " ") === value)) }
                    D.DDropdown { Layout.fillWidth: true; options: ["Standard servers"].concat(root.vpn.groups.map(g => g.replace(/_/g, " "))); currentValue: root.group ? root.group.replace(/_/g, " ") : "Standard servers"; onValueChanged: value => root.group = value === "Standard servers" ? "" : root.vpn.groups.find(g => g.replace(/_/g, " ") === value) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    D.DButton { text: "Fastest"; onClicked: { root.selectCountry(""); root.group = ""; } }
                    D.DButton { text: "Connect to selection"; Layout.fillWidth: true; enabled: root.vpn.ready && !root.vpn.busy && (!root.region || !!root.city); onClicked: root.connectSelection() }
                }
            }
            D.DFlickable {
                id: settingsScroll
                objectName: "settingsScroll"
                clip: true
                contentWidth: width
                contentHeight: settingsColumn.implicitHeight
                verticalScrollBar.objectName: "settingsScrollbar"
                ColumnLayout {
                    id: settingsColumn
                    objectName: "settingsColumn"
                    width: settingsScroll.width
                    spacing: Theme.spacingS
                    D.StyledText { font.pixelSize: Theme.fontSizeMedium; text: root.vpn.settingsError || (root.vpn.ready ? "Connection and privacy" : "Settings load when NordVPN is available."); color: Theme.surfaceVariantText; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    D.DCard {
                        id: connectionCard
                        visible: root.vpn.hasSetting("technology")
                        Layout.fillWidth: true
                        Layout.preferredHeight: connectionOptions.implicitHeight + pad * 2
                        ColumnLayout {
                            id: connectionOptions
                            anchors.fill: parent; spacing: Theme.spacingS
                            RowLayout {
                                Layout.fillWidth: true
                                D.StyledText { font.pixelSize: Theme.fontSizeMedium; text: "VPN technology"; color: connectionCard.contentColor; Layout.fillWidth: true }
                                D.DDropdown { options: root.vpn.capabilities.technologies || ["NORDLYNX", "OPENVPN", "NORDWHISPER"]; currentValue: (root.vpn.settings.technology || "").toUpperCase(); enabled: !root.vpn.busy; onValueChanged: value => root.vpn.setOption("technology", value) }
                            }
                            RowLayout {
                                visible: root.vpn.hasSetting("protocol") && (root.vpn.settings.technology || "").toUpperCase() === "OPENVPN"
                                Layout.fillWidth: true
                                D.StyledText { font.pixelSize: Theme.fontSizeMedium; text: "OpenVPN transport"; color: connectionCard.contentColor; Layout.fillWidth: true }
                                D.DDropdown { options: ["UDP", "TCP"]; currentValue: (root.vpn.settings.protocol || "").toUpperCase(); enabled: !root.vpn.busy; onValueChanged: value => root.vpn.setOption("protocol", value) }
                            }
                        }
                    }
                    Repeater {
                        model: [
                            { key: "killswitch", label: "Kill Switch", detail: "Blocks internet traffic while disconnected." },
                            { key: "autoconnect", label: "Auto-connect", detail: "Connect automatically when the system starts." },
                            { key: "protection", label: "Real-time protection", detail: "Uses Nord DNS. Enabling this turns off custom DNS." },
                            { key: "post-quantum", label: "Post-quantum protection", detail: "Standard NordLynx servers only; incompatible with Meshnet." },
                            { key: "lan-discovery", label: "LAN discovery", detail: "Access printers and devices on your local network." },
                            { key: "obfuscate", label: "Obfuscated servers", detail: "Requires a compatible OpenVPN configuration." },
                            { key: "virtual-location", label: "Virtual locations", detail: "Allow servers hosted outside their represented country." },
                            { key: "notify", label: "NordVPN notifications", detail: "Use the client's desktop notifications." },
                            { key: "meshnet", label: "Meshnet", detail: "Enable Meshnet; peer management is planned." },
                            { key: "ech", label: "Encrypted Client Hello", detail: "Available with NordWhisper." },
                            { key: "analytics", label: "Share performance data", detail: "Allow NordVPN's optional analytics." }
                        ]
                        delegate: D.DCard {
                            id: preferenceCard
                            required property var modelData
                            visible: root.vpn.hasSetting(modelData.key)
                            Layout.fillWidth: true
                            Layout.preferredHeight: preferenceRow.implicitHeight + pad * 2
                            RowLayout {
                                id: preferenceRow
                                anchors.fill: parent; spacing: Theme.spacingM
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: Theme.spacingXXS
                                    D.StyledText { font.pixelSize: Theme.fontSizeMedium; text: preferenceCard.modelData.label; color: preferenceCard.contentColor; Layout.fillWidth: true; font.weight: Theme.fontWeightMedium }
                                    D.StyledText { text: preferenceCard.modelData.detail; color: preferenceCard.mutedColor; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                                }
                                D.DToggle {
                                    checked: root.vpn.settings[preferenceCard.modelData.key] === true
                                    enabled: !root.vpn.busy && (preferenceCard.modelData.key !== "post-quantum" || checked || ((root.vpn.settings.technology || "").toUpperCase() === "NORDLYNX" && root.vpn.settings.meshnet !== true))
                                    toggling: root.vpn.busy
                                    Accessible.name: preferenceCard.modelData.label
                                    onToggled: checked => root.vpn.setOption(preferenceCard.modelData.key, checked)
                                }
                            }
                        }
                    }
                    D.DCard {
                        id: dnsCard
                        visible: root.vpn.hasSetting("dns")
                        Layout.fillWidth: true
                        Layout.preferredHeight: dnsContent.implicitHeight + pad * 2
                        ColumnLayout {
                            id: dnsContent
                            anchors.fill: parent; spacing: Theme.spacingS
                            D.StyledText { font.pixelSize: Theme.fontSizeMedium; text: "Custom DNS"; color: dnsCard.contentColor; font.weight: Theme.fontWeightMedium }
                            D.StyledText { text: "Disables real-time protection. Enter up to three IPv4 addresses, separated by spaces, or off."; color: dnsCard.mutedColor; Layout.fillWidth: true; wrapMode: Text.WordWrap; font.pixelSize: Theme.fontSizeSmall }
                            RowLayout {
                                Layout.fillWidth: true
                                D.DTextField { id: dns; objectName: "dnsInput"; placeholderText: root.vpn.settings.dns || "off"; Layout.fillWidth: true }
                                D.DButton { text: "Apply"; enabled: !root.vpn.busy && !!dns.text.trim(); onClicked: root.vpn.setOption("dns", dns.text.trim()) }
                            }
                        }
                    }
                    D.StyledText { text: root.vpn.version; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                }
            }
        }
    }
}
