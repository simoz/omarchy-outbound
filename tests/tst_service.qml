import QtQuick
import QtTest
import ".." as Plugin

Item {
    Plugin.Service { id: service }
    TestCase {
        name: "OutboundService"
        function init() {
            service.setScenario("sample");
        }
        function test_selection_tracks_combined_filters() {
            compare(service.rows.length, 18);
            compare(service.countryCount, 8);
            service.selection = "demo-0";
            verify(service.selected !== null);
            service.family = "IPv4";
            compare(service.selection, "");
            compare(service.selected, null);
            service.country = "unknown";
            compare(service.filtered.length, 1);
            compare(service.filtered[0].app, "Unknown process");
            service.chooseCountry("unknown");
            compare(service.country, "");
        }
        function test_scenario_resets_stale_filters_and_selection() {
            service.query = "no match";
            service.application = "Browser";
            service.selection = "demo-0";
            service.setScenario("empty");
            compare(service.query, "");
            compare(service.application, "");
            compare(service.filtered.length, 0);
            compare(service.selection, "");
            service.setScenario("error");
            compare(service.filtered.length, 0);
            service.setScenario("busy");
            compare(service.filtered.length, 240);
        }
    }
}
