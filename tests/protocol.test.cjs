const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const protocol = vm.createContext({});
vm.runInContext(fs.readFileSync(require('node:path').join(__dirname,'../Protocol.js'),'utf8'),protocol);
function snapshot() {
    return {version:1,kind:'snapshot',requestId:'r-1',session:'a'.repeat(32),sequence:1,observedAtMs:1800000000000,status:'partial',
        connections:[{id:'socket-1',family:'IPv6',local:{address:'::1',port:12},remote:{address:'::ffff:8.8.8.8',port:443},state:'ESTABLISHED',uid:1000,direction:'unknown',scope:'public',country:'IT',owners:[{pid:1,startTimeTicks:'15',name:'A'},{pid:2,startTimeTicks:'16',name:'B'}]}],
        coverage:{ipv4:null,ipv6:null,namespace:'current',omittedRows:0,truncated:false,processes:{denied:1,races:0,errors:0,ownersOmitted:0,timedOut:false,scanLimited:false}},
        database:{state:'missing',buildEpochSeconds:null,releaseMonth:null,stale:false,lookupErrors:0},
        aggregates:{sockets:1,countries:{IT:1},applications:{A:1,B:1},unknownOwners:0}};
}
test('validates snapshots and preserves shared owners as one socket',()=>{
    const s=protocol.parse(JSON.stringify(snapshot()),'r-1','',0);
    const rows=protocol.rows(s);
    assert.equal(rows.length,1); assert.equal(rows[0].app,'A / B'); assert.equal(rows[0].apps.length,2);
});
test('rejects bad schema, repeated sessions/sequences and inconsistent aggregates',()=>{
    const changes=[s=>s.version=2,s=>s.requestId='late',s=>s.connections[0].remote.port=65536,s=>s.connections[0].remote.address=':::1',s=>s.connections[0].owners[0].name='bad\nname',s=>s.aggregates.sockets=2,s=>s.aggregates.countries.IT=2,s=>s.connections[0].direction='outbound',s=>s.connections.push(s.connections[0]),s=>s.coverage.processes.errors=-1,s=>s.database.state='made-up'];
    changes.forEach(change=>{const s=snapshot();change(s);assert.throws(()=>protocol.parse(JSON.stringify(s),'r-1','',0));});
    assert.throws(()=>protocol.parse(JSON.stringify(snapshot()),'r-1','b'.repeat(32),0));
    assert.throws(()=>protocol.parse(JSON.stringify(snapshot()),'r-1','',1));
});
test('bounds unterminated output and reconstructs ASCII Unicode escapes at every split',()=>{
    const s=snapshot(); s.connections[0].owners[0].name='船🦀';s.aggregates.applications={'船🦀':1,B:1};
    const line=JSON.stringify(s).replace(/[\u007f-\uffff]/g,c=>'\\u'+c.charCodeAt(0).toString(16).padStart(4,'0'))+'\n';
    for(let i=0;i<line.length;i++) {
        const a=protocol.frame('',line.slice(0,i)), b=protocol.frame(a.buffer,line.slice(i));
        assert.equal(protocol.parse(b.lines[0],'r-1','',0).connections[0].owners[0].name,'船🦀');
    }
    assert.throws(()=>protocol.frame('x'.repeat(protocol.maxLine-1),'x'));
    assert.throws(()=>protocol.frame('','x'.repeat(protocol.maxLine+1)));
    assert.throws(()=>protocol.frame('','é'));
    assert.throws(()=>protocol.frame('','{}\n{}\n'));
    assert.throws(()=>protocol.parse('['.repeat(9)+']'.repeat(9),'r-1','',0));
});
test('IP validation handles compressed and mapped IPv6 without accepting broken forms',()=>{
    for(const ip of ['::','::1','2001:db8::1','::ffff:192.0.2.1','1:2:3:4:5:6:7:8']) assert.ok(protocol.ip(ip,'IPv6'),ip);
    for(const ip of [':::','1:::2','::1:','1:2:3','1:2:3:4:5:6:7:8:9','::ffff:999.0.0.1']) assert.ok(!protocol.ip(ip,'IPv6'),ip);
});
