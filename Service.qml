import QtQuick
import "fixtures/Demo.js" as Demo
import "Model.js" as Model

Item {
    id: root
    property var shell: null
    property var manifest: null
    property string scenario: "sample"
    property string query: ""
    property string application: ""
    property string country: ""
    property string family: ""
    property string selection: ""
    property bool reducedMotion: true
    property bool scanlines: false
    property bool glow: true
    readonly property var countries: Demo.countries
    readonly property var rows: Demo.connections(scenario)
    readonly property var filtered: Model.filter(rows, query, application, country, family)
    readonly property var selected: Model.selected(filtered, selection)
    readonly property var applications: Model.groups(rows, "app")
    // Faceted counts ignore their own filter so choosing a country stays reversible.
    readonly property var destinations: Model.groups(Model.filter(rows, query, application, "", family), "country")
    readonly property var countryApplications: Model.groups(Model.filter(rows, query, "", country, family), "app")
    readonly property int countryCount: Model.groups(rows.filter(function(row) {
        return row.country && row.country !== "local" && row.country !== "unknown";
    }), "country").length

    function clearFilters() {
        query = "";
        application = "";
        country = "";
        family = "";
    }

    function chooseCountry(code) {
        country = country === code ? "" : code;
    }

    function chooseApplication(name) { application = application === name ? "" : name; }
    function countryBadge(code) { return Model.countryBadge(code); }
    function appBadge(name) { return Model.appBadge(name); }

    function setScenario(value) {
        clearFilters();
        selection = "";
        scenario = value;
    }

    function countryName(code) { return Model.countryName(code, countries); }
    onFilteredChanged: if (!Model.selected(filtered, selection)) selection = ""
}
