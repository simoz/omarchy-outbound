import QtQuick
import QtTest
import ".." as Plugin
import "fixtures/Connections.js" as Fixture

Item {
    Plugin.Service { id: service }
    TestCase {
        name: "OutboundService"
        function init() {
            service.clearFilters();
            service.selection = "";
            service.liveRows = Fixture.connections("sample");
            service.origin = {lon:12.5, lat:41.9};
        }
        function test_view_demand_counts_all_monitors_and_preserves_pause() {
            service.setView("monitor-a",false);
            service.setView("monitor-b",true);
            verify(service.demanded);
            compare(service.openViews,1);
            compare(service.pollInterval,2000);
            service.removeView("monitor-b");
            verify(service.demanded);
            compare(service.pollInterval,10000);
            service.paused = true;
            verify(!service.demanded);
            service.setView("monitor-a",true);
            verify(!service.demanded);
            service.removeView("monitor-a");
            service.paused = false;
            verify(!service.demanded);
        }
        function test_configuration_validates_origin_without_inventing_one() {
            compare(service.configure("relative","","","","2"),"Use absolute file paths.");
            verify(service.configure("/tmp/engine","","91","0","2") !== "");
            verify(service.configure("/tmp/engine","","","0","2") !== "");
            compare(service.configure("/tmp/engine","","41.9","12.5","3"),"");
            compare(service.origin.lat,41.9);
            compare(service.intervalSeconds,3);
            compare(service.configure("","","","","2"),"");
            compare(service.origin,null);
        }
        function test_selection_tracks_combined_filters() {
            compare(service.rows.length, 24);
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
        function test_empty_snapshot_clears_selection_without_inventing_rows() {
            service.selection = "demo-0";
            service.liveRows = [];
            compare(service.rows.length, 0);
            compare(service.filtered.length, 0);
            compare(service.selection, "");
        }
        function test_country_application_drilldown_retains_facet_totals() {
            service.chooseCountry("DE");
            compare(service.filtered.length, 8);
            compare(service.countryApplications.reduce(function(n, g) { return n + g.count; }, 0), 8);
            service.chooseApplication("Browser");
            compare(service.filtered.length, 2);
            compare(service.countryApplications.reduce(function(n, g) { return n + g.count; }, 0), 8);
            service.chooseApplication("Browser");
            compare(service.filtered.length, 8);
        }
    }
}
