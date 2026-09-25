const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
function load(file) {
    const context = vm.createContext({});
    vm.runInContext(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'), context);
    return context;
}
const model = load('Model.js');
const demo = load('tests/fixtures/Connections.js');
const projection = load('ui/Projection.js');

test('filters combine without losing unknown and local rows', () => {
    const rows = demo.connections('sample');
    assert.equal(rows.length, 24);
    assert.equal(model.filter(rows, '', '', 'unknown', '').length, 1);
    assert.equal(model.filter(rows, '', '', 'local', '').length, 1);
    assert.equal(model.filter(rows, '2001:DB8', '', '', 'IPv4').length, 0);
    const found = model.filter(rows, 'browser', 'Browser', 'US', 'IPv6');
    assert.equal(found.length, 1);
    assert.equal(found[0].id, 'demo-0');
    assert.equal(model.selected(found, 'demo-1'), null);
});

test('scenario totals and facet counts refer to emitted sockets', () => {
    for (const scenario of ['sample', 'busy', 'empty', 'error']) {
        const rows = demo.connections(scenario);
        assert.equal(model.groups(rows, 'app').reduce((n, g) => n + g.count, 0), rows.length);
        assert.equal(new Set(rows.map(r => r.id)).size, rows.length);
        assert.ok(rows.every(r => r.direction === 'Unknown'));
    }
    assert.equal(demo.connections('busy').length, 240);
});

test('orthographic projection hides back hemisphere and clips crossings at limb', () => {
    assert.ok(projection.project(180, 0, 0, 0).z < 0);
    const path = projection.path([[80, 0], [100, 0]], 0, 0, 100, 120, 120);
    assert.equal(path.length, 2);
    assert.equal(path[0][0], 'M');
    assert.equal(path[1][0], 'L');
    assert.ok(Math.abs(path[1][1] - 220) < 0.001);
    const hidden = projection.path([[150, 10], [160, 20]], 0, 0, 100, 120, 120);
    assert.equal(hidden.length, 0);
    assert.equal(projection.wrap(190), -170);
    assert.equal(projection.wrap(-190), 170);
});

test('demo arcs and geography produce finite paths in rotated views', () => {
    const geography = load('assets/Countries.js');
    for (const lon of [-179, 0, 179]) {
        const paths = projection.paths(geography.outlines, lon, 70, 100, 120, 120);
        assert.ok(paths.length > 0);
        assert.ok(paths.every(p => Number.isFinite(p[1]) && Number.isFinite(p[2])));
    }
    for (const country of demo.countries) {
        const arc = projection.arc([12.5, 41.9], [country.lon, country.lat]);
        assert.ok(arc.every(p => Number.isFinite(p[0]) && Number.isFinite(p[1])));
        assert.ok(Math.abs(arc.at(-1)[0] - country.lon) < 1e-8);
    }
});


test('shared process names stay separate facets and prototype names are plain data', () => {
    const rows = [
        {id:'a', app:'Editor, __proto__', apps:['Editor', '__proto__'], country:'IT'},
        {id:'b', app:'Editor', apps:['Editor'], country:'IT'}
    ];
    const groups = model.groups(rows, 'app');
    assert.equal(groups.find(g => g.value === 'Editor').count, 2);
    assert.equal(groups.find(g => g.value === '__proto__').count, 1);
    assert.equal(model.filter(rows, '', '__proto__', '', '').length, 1);
});
