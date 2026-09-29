import QtQuick
import QtTest
import ".." as Plugin
import "fixtures/Connections.js" as Fixture

Item {
    Plugin.Service { id: service }
    TestCase {
        name: "OutboundService"
        function init() {
            service.views = [];
            service.paused = false;
            service.intervalSeconds = 2;
            service.clearFilters();
            service.selection = "";
            service.liveRows = Fixture.connections("sample");
            service.origin = {lon:12.5, lat:41.9};
        }
        function test_view_demand_counts_all_monitors_and_preserves_pause() {
            service.setView("monitor-a",false);
            verify(!service.demanded);
            compare(service.status,"IDLE");
            service.setView("monitor-b",true);
            verify(service.demanded);
            compare(service.openViews,1);
            compare(service.pollInterval,2000);
            service.removeView("monitor-b");
            verify(!service.demanded);
            compare(service.status,"IDLE");
            service.paused = true;
            verify(!service.demanded);
            service.setView("monitor-a",true);
            verify(!service.demanded);
            compare(service.status,"PAUSED");
            service.removeView("monitor-a");
            service.paused = false;
            verify(!service.demanded);
        }
        function test_snapshot_lives_until_last_open_view_closes() {
            service.setView("monitor-a",true);
            service.setView("monitor-b",true);
            var snapshot = {sequence:1, database:{state:"missing"},
                coverage:{ipv4:null, ipv6:null, omittedRows:0,
                    processes:{denied:0, races:0, errors:0, ownersOmitted:0}},
                aggregates:{unknownOwners:0}};
            service.snapshot = snapshot;
            service.selection = "demo-0";
            service.query = "Browser";
            service.paused = true;
            compare(service.snapshot,snapshot);
            compare(service.rows.length,24);
            service.setView("monitor-a",false);
            compare(service.snapshot,snapshot);
            compare(service.rows.length,24);
            compare(service.selection,"demo-0");
            service.removeView("monitor-b");
            compare(service.snapshot,null);
            compare(service.rows.length,0);
            compare(service.selection,"");
            compare(service.query,"Browser");
            service.setView("monitor-a",true);
            verify(!service.demanded);
            compare(service.snapshot,null);
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
        function test_unchanged_configuration_is_saved_without_error() {
            var stored = null, writes = 0;
            // Mirrors the shell: an identical entry is reported as not updated.
            service.saveConfiguration = function(config) {
                var same = JSON.stringify(config) === JSON.stringify(stored);
                stored = config; writes++; return !same;
            };
            compare(service.configure("/tmp/engine","","","","4"),"");
            compare(service.configure("/tmp/engine","","","","4"),"");
            compare(writes,1);
            stored = null;
            service.saveConfiguration = function() { return false; };
            compare(service.configure("/tmp/engine","","","","5"),"Unable to save settings.");
            compare(service.intervalSeconds,4);
            service.saveConfiguration = null;
            compare(service.configure("","","","","2"),"");
        }
        function test_display_effects_persist_with_other_settings() {
            var stored = null;
            service.saveConfiguration = function(config) { stored = config; return true; };
            compare(service.configure("/tmp/engine","","","","3"),"");
            verify(!service.reducedMotion && service.glow && service.scanlines);
            compare(service.setDisplay("reducedMotion",true),"");
            compare(service.setDisplay("scanlines",false),"");
            verify(service.reducedMotion && service.glow && !service.scanlines);
            compare(stored.backendPath,"/tmp/engine");
            compare(stored.reducedMotion,true);
            // Later edits keep display choices, and a reload restores them.
            compare(service.configure("/tmp/engine","","","","4"),"");
            compare(stored.scanlines,false);
            service.loadConfiguration({intervalSeconds:2});
            verify(!service.reducedMotion && service.glow && service.scanlines);
            service.loadConfiguration(stored);
            verify(service.reducedMotion && !service.scanlines);
            service.saveConfiguration = null;
            service.loadConfiguration({});
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
