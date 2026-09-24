# Map geometry

Made with Natural Earth. The source data is in the public domain.

- Dataset: Natural Earth 1:110m Admin 0 Countries, version 5.1.1.
- [Original GeoJSON](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.1/geojson/ne_110m_admin_0_countries.geojson)
- SHA-256: `6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f`
- [Terms](https://www.naturalearthdata.com/about/terms-of-use/)
- Conversion: `python3 -B tools/prepare_geometry.py /path/to/input.geojson`.

`Countries.js` retains exterior polygon vertices rounded to three decimal
places, omitting holes. It is a low-resolution illustrative
outline with de facto boundaries, not a political or navigational reference.
It also includes 5,341 land dots sampled from those exterior rings at roughly
1.5-degree spacing, adjusted by latitude.
The conversion is offline and refuses an input with a different checksum.

The generated file also contains 175 country label anchors from `ISO_A2_EH`,
`NAME_EN`, `LABEL_X` and `LABEL_Y`. These are illustrative country markers, not
remote-host locations. Codes without an anchor remain visible in lists but are
not plotted. Demo IP-country assignments are explicitly simulated. No GeoIP
database is bundled; live lookup requires an explicitly supplied local MMDB.
