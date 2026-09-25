import QtQuick
import QtTest
import qs.Commons
import ".." as Plugin
import "../ui" as Outbound

Item {
    width: 1000
    height: 900
    Plugin.Service { id: service }
    Outbound.Dashboard {
        id: dashboard
        width: parent.width
        height: parent.height
        service: service
    }
    SignalSpy { id: closeSpy; target: dashboard; signalName: "closeRequested" }
    SignalSpy { id: copySpy; target: dashboard; signalName: "copyRequested" }
    TestCase {
        name: "OutboundDashboard"
        when: windowShown
        function init() {
            service.setScenario("sample");
            service.reducedMotion = true;
            dashboard.active = true;
            dashboard.globe.reset();
            closeSpy.clear();
            copySpy.clear();
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
        function test_live_globe_requires_manual_origin_for_arcs() {
            service.liveRows = [{id:"live-1", app:"Test", country:"IT", family:"IPv4", ip:"1.1.1.1"}];
            service.origin = null;
            service.demoMode = false;
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
        function test_globe_keyboard_country_and_motion() {
            dashboard.globe.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(dashboard.globe.longitude, -7);
            service.chooseCountry("JP");
            compare(dashboard.globe.longitude, 138);
            compare(dashboard.globe.latitude, 37);
            dashboard.globe.rotating = true;
            wait(90);
            compare(dashboard.globe.longitude, 138);
            service.reducedMotion = false;
            tryVerify(function() { return dashboard.globe.longitude !== 138; });
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
            service.setScenario("busy");
            wait(20);
            var first = findChild(dashboard, "connection-demo-0");
            verify(first !== null);
            first.forceActiveFocus();
            for (var i = 0; i < 12; i++) keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Space);
            compare(service.selection, "demo-12");
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
