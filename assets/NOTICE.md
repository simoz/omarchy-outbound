# Map geometry

Made with Natural Earth. The source data is in the public domain.

- Dataset: Natural Earth 1:110m Admin 0 Countries, version 5.1.1.
- [Original GeoJSON](https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.1/geojson/ne_110m_admin_0_countries.geojson)
- SHA-256: `6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f`
- [Terms](https://www.naturalearthdata.com/about/terms-of-use/)
- Conversion: `python3 -B tools/prepare_geometry.py /path/to/input.geojson`.

`Countries.js` retains exterior polygon vertices rounded to three decimal
places, omitting holes and properties. It is a low-resolution illustrative
outline with de facto boundaries, not a political or navigational reference.
The conversion is offline and refuses an input with a different checksum.

The prototype's country markers and IP-country assignments are explicitly
simulated. No GeoIP database is included or queried.
