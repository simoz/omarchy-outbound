import QtQuick
import QtTest
import qs.Commons
import ".." as Plugin
import "fixtures/Connections.js" as Fixture
import "../ui" as Outbound

Item {
    width: 1000
    height: 900
    Plugin.Service {
        id: service
        property int refreshCount: 0
        function refresh() { refreshCount++; }
    }
    Outbound.Dashboard {
        id: dashboard
        width: parent.width
        height: parent.height
        service: service
    }
    SignalSpy { id: expandSpy; target: dashboard; signalName: "expandRequested" }
    SignalSpy { id: closeSpy; target: dashboard; signalName: "closeRequested" }
    SignalSpy { id: copySpy; target: dashboard; signalName: "copyRequested" }
    TestCase {
        name: "OutboundDashboard"
        when: windowShown
        function init() {
            service.clearFilters();
            service.selection = "";
            service.liveRows = Fixture.connections("sample");
            service.origin = {lon:12.5, lat:41.9};
            service.reducedMotion = true;
            dashboard.active = true;
            dashboard.globe.reset();
            closeSpy.clear();
            copySpy.clear();
        }
        function test_action_shortcuts_and_shared_button_behavior() {
            var listToggle = findChild(dashboard, "connectionListToggleButton");
            var table = listToggle.parent;
            var refresh = findChild(dashboard, "refreshButton");
            table.expanded = false;
            service.paused = true;
            service.refreshCount = 0;
            dashboard.globe.rotating = false;
            findChild(dashboard, "refreshButton").forceActiveFocus();
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 1);
            verify(service.paused);
            refresh.enabled = false;
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 1);
            refresh.enabled = Qt.binding(function() { return !service.refreshing && !service.engineInstalling && !service.geoInstalling; });
            keyClick(Qt.Key_P, Qt.ControlModifier);
            verify(!service.paused);
            keyClick(Qt.Key_G, Qt.ControlModifier);
            verify(dashboard.globe.rotating);
            keyClick(Qt.Key_G, Qt.ControlModifier);
            verify(!dashboard.globe.rotating);
            expandSpy.clear();
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(expandSpy.count, 1);
            dashboard.surfaceSwitchAvailable = false;
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(expandSpy.count, 1);
            dashboard.surfaceSwitchAvailable = true;
            dashboard.globe.forceActiveFocus();
            keyClick(Qt.Key_L, Qt.ControlModifier);
            verify(table.expanded);
            verify(listToggle.activeFocus);
            keyClick(Qt.Key_L, Qt.ControlModifier);
            verify(!table.expanded);
            keyClick(Qt.Key_L, Qt.ControlModifier);
            verify(table.expanded);
            service.query = "Browser";
            keyClick(Qt.Key_F, Qt.ControlModifier);
            verify(!table.expanded);
            verify(dashboard.searchField.activeFocus);
            compare(dashboard.searchField.selectedText, "Browser");
            findChild(dashboard, "refreshButton").forceActiveFocus();
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier);
            compare(service.query, "");
            service.selection = service.filtered[0].id;
            keyClick(Qt.Key_C, Qt.ControlModifier);
            compare(copySpy.count, 1);
            compare(copySpy.signalArguments[0][0], service.selected.ip);
            keyClick(Qt.Key_Comma, Qt.ControlModifier);
            var settings = findChild(dashboard, "outboundSettings");
            tryCompare(settings, "opened", true);
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 1);
            settings.close();
        }
        function test_shortcuts_preserve_editing_popups_and_desktop_modifiers() {
            service.refreshCount = 0;
            service.paused = true;
            service.query = "Browser";
            dashboard.searchField.forceActiveFocus();
            keyClick(Qt.Key_P, Qt.ControlModifier);
            keyClick(Qt.Key_R, Qt.ControlModifier);
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier);
            verify(service.paused);
            compare(service.refreshCount, 0);
            compare(service.query, "Browser");
            keyClick(Qt.Key_A, Qt.ControlModifier);
            compare(dashboard.searchField.selectedText, "Browser");
            keyClick(Qt.Key_C, Qt.ControlModifier);
            compare(copySpy.count, 0);
            keyClick(Qt.Key_X);
            compare(service.query, "x");
            findChild(dashboard, "refreshButton").forceActiveFocus();
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.MetaModifier);
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.AltModifier);
            compare(service.refreshCount, 0);
            dashboard.active = false;
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 0);
            dashboard.active = true;
            keyClick(Qt.Key_F1);
            var help = findChild(dashboard, "outboundKeyboardHelp");
            tryCompare(help, "opened", true);
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 0);
            help.close();
            var family = findChild(dashboard, "familyFilter");
            family.forceActiveFocus();
            family.popup.open();
            tryCompare(family.popup, "opened", true);
            keyClick(Qt.Key_R, Qt.ControlModifier);
            compare(service.refreshCount, 0);
            family.popup.close();
            service.paused = false;
        }
        function test_collection_toggle_preserves_rows_and_globe_rotation() {
            var toggle = findChild(dashboard, "collectionToggleButton");
            service.paused = false;
            service.phase = "partial";
            service.error = "";
            dashboard.globe.rotating = true;
            var rows = service.liveRows;
            compare(toggle.text, "● LIVE");
            mouseClick(toggle);
            verify(service.paused);
            compare(toggle.text, "Ⅱ PAUSED");
            verify(dashboard.globe.rotating);
            compare(service.liveRows, rows);
            toggle.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(!service.paused);
            compare(toggle.text, "● LIVE");
            service.error = "Socket collection failed.";
            compare(toggle.text, "! ERROR");
            service.error = "";
            service.phase = "idle";
            dashboard.globe.rotating = false;
        }
        function test_refresh_mouse_and_keyboard_preserve_view_state() {
            var refresh = findChild(dashboard, "refreshButton");
            service.refreshCount = 0;
            service.paused = true;
            service.query = "Browser";
            dashboard.globe.zoom = 2;
            var rows = service.liveRows;
            mouseClick(refresh);
            compare(service.refreshCount,1);
            refresh.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(service.refreshCount,2);
            verify(service.paused);
            compare(service.query,"Browser");
            compare(service.liveRows,rows);
            compare(dashboard.globe.zoom,2);
            dashboard.width = 380;
            tryVerify(function() { return refresh.mapToItem(dashboard,refresh.width,0).x <= dashboard.width; });
            var expand = findChild(dashboard,"surfaceSwitchButton");
            tryVerify(function() { return expand.mapToItem(dashboard,expand.width,0).x <= dashboard.width; });
            dashboard.width = 1000;
            service.paused = false;
        }
        function test_globe_rotation_control_remains_available_in_narrow_view() {
            dashboard.width = 380;
            var play = findChild(dashboard, "globeRotationButton");
            verify(play.visible);
            var origin = findChild(dashboard, "setGlobeOriginButton");
            var playBottom = play.mapToItem(dashboard.globe, 0, play.height);
            verify(playBottom.y <= origin.y);
            dashboard.globe.rotating = false;
            service.paused = true;
            play.clicked();
            verify(dashboard.globe.rotating);
            verify(service.paused);
            play.clicked();
            verify(!dashboard.globe.rotating);
            service.paused = false;
            dashboard.width = 1000;
        }
        function test_keyboard_guide_restores_focus_and_keeps_escape_local() {
            dashboard.searchField.forceActiveFocus();
            keyClick(Qt.Key_F1);
            var help = findChild(dashboard, "outboundKeyboardHelp");
            tryCompare(help, "opened", true);
            var guideScroll = findChild(help, "keyboardHelpScroll");
            keyClick(Qt.Key_PageDown);
            verify(guideScroll.contentY > 0);
            keyClick(Qt.Key_Escape);
            tryCompare(help, "opened", false);
            compare(closeSpy.count, 0);
            verify(dashboard.searchField.activeFocus);
            keyClick(Qt.Key_B);
            compare(service.query, "b");
            keyClick(Qt.Key_F1);
            tryCompare(help, "opened", true);
            compare(guideScroll.contentY, 0);
            keyClick(Qt.Key_F1);
            tryCompare(help, "opened", false);
        }
        function test_keyboard_search_and_escape() {
            dashboard.searchField.forceActiveFocus();
            keyClick(Qt.Key_B);
            keyClick(Qt.Key_R);
            compare(service.query, "br");
            verify(service.filtered.length > 0);
            keyClick(Qt.Key_Left);
            compare(dashboard.globe.longitude, -15);
            keyClick(Qt.Key_Escape);
            compare(closeSpy.count, 1);
        }
        function test_globe_zoom_inputs_limits_and_reset() {
            var globe = dashboard.globe;
            var baseRadius = globe.radius;
            globe.forceActiveFocus();
            keyClick(Qt.Key_Plus);
            verify(globe.zoom > 1);
            fuzzyCompare(globe.radius, baseRadius * globe.zoom, 0.001);
            keyClick(Qt.Key_Minus);
            fuzzyCompare(globe.zoom, 1, 0.001);
            var navigation = findChild(globe, "globeNavigation");
            mouseWheel(navigation, 20, 20, 0, 120);
            verify(globe.zoom > 1);
            globe.zoomBy(100);
            compare(globe.zoom, globe.maximumZoom);
            verify(!findChild(dashboard, "globeZoomIn").enabled);
            globe.zoomBy(-100);
            compare(globe.zoom, 1);
            verify(!findChild(dashboard, "globeZoomOut").enabled);
            findChild(dashboard, "globeZoomIn").clicked();
            verify(globe.zoom > 1);
            var savedZoom = globe.zoom;
            dashboard.width = 760;
            compare(globe.zoom, savedZoom);
            dashboard.width = 1000;
            globe.forceActiveFocus();
            keyClick(Qt.Key_Home);
            compare(globe.zoom, 1);
            compare(globe.longitude, -15);
            compare(globe.latitude, 18);
            dashboard.searchField.forceActiveFocus();
            keyClick(Qt.Key_Plus);
            compare(globe.zoom, 1);
            service.query = "";
        }
        function test_live_globe_requires_manual_origin_for_arcs() {
            service.liveRows = [{id:"live-1", app:"Test", country:"IT", family:"IPv4", ip:"1.1.1.1"}];
            service.origin = null;
            compare(dashboard.globe.destinations.length, 1);
            compare(dashboard.globe.layers[2].length, 0);
            service.origin = {lon:0, lat:45};
            verify(dashboard.globe.layers[2].length > 0);
            service.origin = null;
            compare(dashboard.globe.layers[2].length, 0);
            service.liveRows = [];
        }
        function test_settings_sections_preserve_drafts_and_footer() {
            var settings = findChild(dashboard, "outboundSettings");
            settings.open();
            tryCompare(settings, "opened", true);
            settings.section = 0;
            var backend = findChild(settings, "backendPathField");
            backend.text = "/tmp/unsaved-backend";
            var globeTab = findChild(settings, "settingsSections").itemAt(1);
            globeTab.forceActiveFocus();
            keyClick(Qt.Key_Space);
            compare(settings.section, 1);
            verify(findChild(settings, "originCityField").visible);
            verify(!backend.visible);
            var apply = findChild(settings, "applyCollectionSettings");
            verify(apply.visible);
            verify(apply.y + apply.height <= apply.parent.height);
            settings.section = 0;
            compare(backend.text, "/tmp/unsaved-backend");
            settings.close();
        }
        function test_done_saves_drafts_and_only_closes_on_success() {
            var settings = findChild(dashboard, "outboundSettings");
            settings.open();
            tryCompare(settings, "opened", true);
            settings.section = 0;
            var backend = findChild(settings, "backendPathField");
            var done = findChild(settings, "applyCollectionSettings");
            var previousBackend = service.backendPath;
            backend.text = "relative/path";
            done.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(settings.opened);
            verify(settings.validationError.length > 0);
            compare(service.backendPath, previousBackend);
            backend.text = "/tmp/outbound-test-backend";
            service.saveConfiguration = function(config) { return false; };
            done.clicked();
            verify(settings.opened);
            compare(settings.validationError, "Unable to save settings.");
            compare(service.backendPath, previousBackend);
            service.saveConfiguration = null;
            done.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryCompare(settings, "opened", false);
            compare(service.backendPath, "/tmp/outbound-test-backend");
            settings.open();
            tryCompare(settings, "opened", true);
            compare(backend.text, "/tmp/outbound-test-backend");
            settings.close();
            service.configure(previousBackend, "", "", "", "2");
        }
        function test_city_choice_populates_and_saves_origin() {
            var settings = findChild(dashboard, "outboundSettings");
            settings.openOrigin();
            tryCompare(settings, "opened", true);
            tryVerify(function() { return findChild(settings, "originCityField").activeFocus; });
            settings.chooseOrigin({label:"Test city, Italy", lat:44.4, lon:8.9});
            compare(service.origin.name, "Test city, Italy");
            compare(service.origin.lat, 44.4);
            compare(findChild(settings, "originLatitude").text, "44.4");
            compare(findChild(settings, "originLongitude").text, "8.9");
            findChild(settings, "applyCollectionSettings").clicked();
            compare(service.origin.name, "Test city, Italy");
            compare(service.origin.lat, 44.4);
            settings.close();
            service.configure("", "", "", "", "2");
        }
        function test_connection_pulse_respects_motion_visibility_and_pause() {
            dashboard.globe.rotating = false;
            service.paused = false;
            var pulse = findChild(dashboard, "connectionPulse");
            verify(!dashboard.globe.linksAnimating);
            service.reducedMotion = false;
            verify(dashboard.globe.linksAnimating);
            wait(100);
            var opacity = pulse.opacity;
            var paints = dashboard.globe.paintCount;
            tryVerify(function() { return Math.abs(pulse.opacity - opacity) > 0.1; });
            compare(dashboard.globe.paintCount, paints);
            service.paused = true;
            verify(!dashboard.globe.linksAnimating);
            service.paused = false;
            dashboard.active = false;
            verify(!dashboard.globe.linksAnimating);
            dashboard.active = true;
            service.reducedMotion = true;
            verify(!dashboard.globe.linksAnimating);
            verify(dashboard.globe.layers[2].length > 0);
        }
        function test_play_after_reduced_motion_remains_available() {
            service.reducedMotion = false;
            var play = findChild(dashboard, "globeRotationButton");
            mouseClick(play);
            verify(dashboard.globe.rotating);
            service.reducedMotion = true;
            verify(!dashboard.globe.rotating);
            verify(play.enabled);
            var longitude = dashboard.globe.longitude;
            play.forceActiveFocus();
            keyClick(Qt.Key_Space);
            tryVerify(function() { return dashboard.globe.longitude !== longitude; });
            verify(service.reducedMotion);
            verify(!dashboard.globe.linksAnimating);
            mouseClick(play);
            verify(!dashboard.globe.rotating);
            longitude = dashboard.globe.longitude;
            wait(90);
            compare(dashboard.globe.longitude, longitude);
        }
        function test_globe_keyboard_country_and_motion() {
            dashboard.globe.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(dashboard.globe.longitude, -7);
            service.chooseCountry("JP");
            var japan = service.countries.find(function(c) { return c.code === "JP"; });
            compare(dashboard.globe.longitude, japan.lon);
            compare(dashboard.globe.latitude, japan.lat);
            service.reducedMotion = false;
            dashboard.globe.rotating = true;
            tryVerify(function() { return dashboard.globe.longitude !== japan.lon; });
            dashboard.active = false;
            var stopped = dashboard.globe.longitude;
            wait(90);
            compare(dashboard.globe.longitude, stopped);
            dashboard.globe.rotating = false;
        }
        function test_theme_reacts_and_copy_uses_selected_row() {
            var before = Color.foreground;
            Color.foreground = "#192837";
            wait(10);
            compare(dashboard.searchField.color.toString(), "#192837");
            var button = findChild(dashboard, "copyIpButton");
            service.selection = "demo-0";
            verify(button.enabled);
            button.clicked();
            compare(copySpy.count, 1);
            compare(copySpy.signalArguments[0][0], "2001:db8::1");
            service.family = "IPv4";
            verify(!button.enabled);
            Color.foreground = before;
        }
        function test_list_keyboard_reaches_virtualized_rows() {
            service.liveRows = Fixture.connections("busy");
            wait(20);
            var first = findChild(dashboard, "connection-demo-0");
            verify(first !== null);
            first.forceActiveFocus();
            for (var i = 0; i < 12; i++) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Space);
            compare(service.selection, "demo-12");
        }
        function test_connection_list_expands_to_page_height() {
            service.liveRows = Fixture.connections("busy");
            var toggle = findChild(dashboard, "connectionListToggleButton");
            var list = findChild(dashboard, "outboundConnections");
            var page = findChild(dashboard, "outboundPage");
            var collapsed = list.height;
            mouseClick(toggle);
            verify(!dashboard.globe.visible);
            tryVerify(function() { return list.height > collapsed * 2; });
            tryVerify(function() { return page.contentHeight <= page.height + 1; });
            compare(toggle.Accessible.name, "Collapse connection list");
            toggle.forceActiveFocus();
            keyClick(Qt.Key_Space);
            verify(dashboard.globe.visible);
            tryCompare(list, "height", collapsed);
        }
        function test_overview_fits_desktop_and_settings_escape_stays_local() {
            var page = findChild(dashboard, "outboundPage");
            tryVerify(function() { return page.contentHeight <= page.height + 1; }, 1000, page.contentHeight + " exceeds " + page.height);
            service.chooseCountry("DE");
            compare(dashboard.globe.destinations.length, 8);
            var applications = findChild(dashboard, "outboundApplications");
            compare(applications.total, 8);
            var button = findChild(dashboard, "displaySettingsButton");
            button.clicked();
            var popup = findChild(dashboard, "outboundSettings");
            tryCompare(popup, "opened", true);
            keyClick(Qt.Key_Escape);
            tryCompare(popup, "opened", false);
            compare(closeSpy.count, 0);
        }
    }
}
