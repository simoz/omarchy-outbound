import QtQuick

Breakdown {
    id: root
    required property var service
    groups: service.destinations
    title: "DESTINATIONS"
    subtitle: "COUNTRY                       SOCKETS / SHARE"
    selectedValue: service.country
    labelFor: function(code) { return root.service.countryName(code); }
    badgeFor: function(code) { return root.service.countryBadge(code); }
    flags: true
    onChosen: function(code) { root.service.chooseCountry(code); }
}
