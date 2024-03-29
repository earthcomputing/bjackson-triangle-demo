/*---------------------------------------------------------------------------------------------
 *  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

const cell_ui = 'cell-ui.html';
const graph_ui = 'graph-ui.html';

if (process.argv.length <= 2) {
    console.log("Usage:", __filename, "<hostname> [<s_port] [<c_port]");
    process.exit(-1);
}
 
// var console = require('syslog-console')('eccf-server');

const hostname = process.argv[2];
const s_port = (process.argv.length > 3) ? process.argv[3] : 3000;
const c_port = (process.argv.length > 4) ? process.argv[4] : 1337;

console.log('hostname:', hostname, s_port, c_port);

var last_ait = {};
var json_data = {};
var last_state = {};
var last_msg = {};

var alt_route = {};
var connected = 0;
var c_socket;

// link status
var port_status = {};
// authenticated link partner
var neighbor = {};
// routing table
var router = {};

var config = {
    "trunc" : -30,
    "verbose" : false,
    "periodic" : false
};

// npm install body-parser express socket.io
var bodyParser = require('body-parser');
var express = require('express');
var app = express();
var http = require('http').Server(app);
var io = require('socket.io')(http);
var net = require('net');
var path = require('path');

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use('/', express.static(path.join(__dirname, '/')));

app.get('/config', function (req, res) {
    var query = req.query;
    for (var i in query) config[i] = query[i];
    if (config.verbose) console.log('config:', req.method, req.url, req.query, config);
    res.send(JSON.stringify(config));
});

// http://localhost:3000/ports
app.get('/ports', function (req, res) {
    var current_state = JSON.stringify(json_data) + JSON.stringify(last_ait);
    if (config.verbose) console.log('GET ports ...', current_state);
    res.send('GET ports ...' + current_state);
    // res.status(status).send(body)
});

// static char *port_name[NUM_INTERFACES] = { "enp6s0", "enp7s0", "enp8s0", "enp9s0" };
// http://localhost:3000/port/3
// http://localhost:3000/port/enp6s0
app.all('/port/:port_id', function (req, res, next) {
    var port = req.params.port_id;
    if (config.verbose) console.log('port ...', req.method, req.url, req.params);
    next();
})

// virtual 'recv' on link
// backdoor JSON : req.body - { inbound machineName msg_type pe_id xmitTime }
app.post('/backdoor/:port_id', function (req, res) {
    var port = req.params.port_id;
    backdoorUpdate(req.body);
    if (config.verbose) console.log('POST backdoor ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

// FIXME : crossing streams here - 

    var machineName = req.body.machineName;
    var pe_id = req.body.pe_id;
    var inbound = req.body.inbound;
    var xmitTime = req.body.xmitTime; // adapter clock
    var msg_type = req.body.msg_type;

    var server_now = Date.now() * 1000.0; // server clock

    if (config.trunc != 0) { console.log('recv', 'POST', xmitTime, msg_type, 'port:', port, 'hint:', hint(port)); }

    var obj = {
        machineName: machineName,
        deviceName: port,
        // linkState:
        // entlState:
        // entlCount:
        // AITSent:
        recvTime: xmitTime,
        AITRecieved: msg_type
    };

    noteDequeue(obj);
    echoServer(obj);

    // json_data[obj.machineName] - JSON : { machineName deviceName linkState entlState entlCount AITSent AITRecieved recvTime }
    var json_txt = JSON.stringify(obj);

    // ensure structure exists (multi-map)
    if (!json_data[obj.machineName]) { json_data[obj.machineName] = {}; }

    // hang onto line for debugging
    json_data[obj.machineName][obj.deviceName] = json_txt;

    res.send('POST backdoor ...' + JSON.stringify(req.params));
});

// /ifconfig - JSON : req.body { epoch pe_id uuid port_no is_border status }
app.post('/ifconfig/:port_id', function (req, res) {
    var port = req.params.port_id;
    ifconfigUpdate(req.body);
    if (config.verbose) console.log('POST ifconfig ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

    // body.status == Disconnected

    // if (hostname != req.body.nickname) { error!! }
    port_status[req.body.port_no] = req.body;
    if (config.trunc != 0) { console.log('ifconfig', 'POST', req.body.epoch, 'port:', port, 'hint:', req.body.nickname, 'border:', req.body.is_border, 'status:', req.body.status); }

    res.send('POST ifconfig ...' + JSON.stringify({parms: req.params, body: req.body}));
});

// /hello - JSON : req.body { epoch pe_id recv_port neighbor xmit_port }
app.post('/hello/:port_id', function (req, res) {
    var port = req.params.port_id;

    // ugh - complex body
    req.body = JSON.parse(req.body.json);

    helloUpdate(req.body);
    if (config.verbose) console.log('POST hello ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

    // if (hostname != req.body.nickname) { error!! }
    neighbor[req.body.port_no] = req.body;
    if (config.trunc != 0) { console.log('hello', 'POST', req.body.epoch, 'port:', port, 'hint:', req.body.nickname, 'neighbor:', req.body.neighbor.hint, 'xmit_port:', req.body.xmit_port); }

    res.send('POST hello ...' + JSON.stringify({parms: req.params, body: req.body}));
});

// /route - JSON : req.body { epoch pe_id op tree in_use may_send parent mask }
app.post('/route/:tree', function (req, res) {
    var tree = req.params.tree;
    routeUpdate(req.body);
    if (config.verbose) console.log('POST route ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

    // if (hostname != req.body.nickname) { error!! }
    router[tree] = req.body;
    if (config.trunc != 0) { console.log('route', 'POST', req.body.epoch, 'tree:', tree, 'op:', req.body.op, 'in_use:', req.body.in_use, 'may_send:', req.body.may_send, 'parent:', req.body.parent, 'mask:', req.body.mask); }

    // var redirect = req.body.alt_route;
    // if (config.trunc != 0) { console.log('route', 'POST', 'port:', port, 'redirect', redirect); }
    // alt_route[port] = redirect;

    res.send('POST route ...' + JSON.stringify({parms: req.params, body: req.body}));
});

// from packet-seq (augmented w/nickname
// /port - JSON : body { ait_code epoch frame msg_id msg_type nickname outbound pe_id tree }
app.post('/port/:port_id', function (req, res) {
    var port = req.params.port_id;

    cellAgentUpdate(req.body);
    // ugh, hack req frame for debug output
    var frame = req.body.frame;
    req.body.frame = null;
    if (config.verbose) console.log('POST port ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

    var host = req.body.pe_id;
    var msg_type = req.body.msg_type;
    if (config.trunc != 0) { console.log('xmit', 'POST', msg_type, 'port:', port, 'hint:', hint(port), 'frame:', frame.substr(config.trunc)); }

    // if (hostname != req.body.nickname) { error!! }
    var linkState = last_state[hostname][port]; // UP/DOWN
    if (linkState != undefined && linkState == 'DOWN') {
        res.status(301).send({status: 301, message: 'link down', type: 'transport'});
        return;
    }

    // WHEN not connected : 301 Moved Permanently
    var body = port_status[port];
    if (body != undefined && body.status == 'Disconnected') {
        res.status(301).send({status: 301, message: 'not connected', type: 'transport'});
        return;
    }

try {
    // HACK
    // verb - ...
    // msg_type - JSON : { verb }
    var obj = JSON.parse(msg_type);

    // fudge things here when route-repair:
    if (obj.verb == 'ECHO') {
        // jigger 'port' based upon routing table
    }

    adapterWrite(port, msg_type);
    res.send('POST port ...' + JSON.stringify(req.params));
}
catch (e) {
    console.log('POST port', 'error: ' + e, 'msg_type:', msg_type);
}
});

// static char *port_name[NUM_INTERFACES] = { "enp6s0", "enp7s0", "enp8s0", "enp9s0" };
function hint(port) {
    var nick = device2host[port];
    if (nick == null) nick = 'bogus';
    return nick;
}

// adapter stream - JSON : { port message }
function adapterWrite(port, message) {
    last_ait[port] = message;
    var o = { 'port': port, 'message': message }
    var json_text = JSON.stringify(o);
    c_socket.write(json_text)
}

// *-update - share with visualizers:

// backdoor-update - JSON : req.body - { inbound machineName msg_type pe_id xmitTime }
function backdoorUpdate(d) {
    if (config.verbose) console.log('backdoor-update:', d);
    io.emit('backdoor-update', d); // earth-update
}

// cellagent-update - JSON : { ait_code epoch frame msg_id msg_type outbound pe_id tree } # w/added nickname
function cellAgentUpdate(d) {
    if (config.verbose) console.log('cellagent-update:', d);
    io.emit('cellagent-update', d);
}

// ifconfig-update - JSON : req.body { epoch pe_id uuid port_no is_border status }
function ifconfigUpdate(d) {
    if (config.verbose) console.log('ifconfig-update:', d);
    io.emit('ifconfig-update', d);
}

// hello-update - JSON : req.body { epoch pe_id* recv_port neighbor* xmit_port }
function helloUpdate(d) {
    if (config.verbose) console.log('hello-update:', d);
    io.emit('hello-update', d);
}

// route-update - JSON : req.body { epoch pe_id op tree in_use may_send parent mask }
function routeUpdate(d) {
    if (config.verbose) console.log('route-update:', d);
    io.emit('route-update', d);
}

app.get('/port/:port_id', function (req, res) {
    var port = req.params.port_id;
    if (config.verbose) console.log('GET port ...', req.params);
    var message = last_ait[port];
    res.send('GET port ...' + JSON.stringify(req.params) + message);
});

app.get('/git-version', function (req, res) {
    res.set('Content-Type', 'text/plain');
    res.sendFile(__dirname + '/.git/refs/heads/master');
});

app.get('/git-config', function (req, res) {
    res.set('Content-Type', 'text/plain');
    res.sendFile(__dirname + '/.git/config');
});

app.get('/' + graph_ui, function (req, res) {
    res.sendFile(__dirname + '/' + graph_ui);
});

app.get('/' + cell_ui, function (req, res) {
    res.sendFile(__dirname + '/' + cell_ui);
});

app.get('/', function (req, res) {
    res.sendFile(__dirname + '/' + cell_ui);
});

// aitMessage { port message }
io.on('connection', function (socket) {
    var endpoint = socket.handshake.address;
    console.log('socket.io', s_port, 'connected, session', socket.id, 'from', endpoint);
    connected = 1;
    // sendPacket - send buttom
    socket.on('aitMessage', function (msg) {
        var port = msg.port;
        var message = msg.message;
        console.log('AIT ' + port + ' ' + message);
        adapterWrite(port, message);
    });
});

http.listen(s_port, function () {
    console.log('listening on *:' + s_port);
});

// machineName deviceName linkState entlState entlCount AITSent AITRecieved
var data = {
    "deviceName" : "enp6s0",
    "linkState" : "UP",
    "entlState" : "HELLO",
    "entlCount" : "990",
    "AITMessage" : "-none-"
};

// earth-update - share with visualizers
// earth-update - JSON : { machineName deviceName linkState entlState entlCount AITSent AITRecieved recvTime }
function earthUpdate(data) {
    if (config.verbose) console.log(data);
    io.emit("earth-update", data);
}

function isBlank(str) {
    return (!str || /^\s*$/.test(str));
}

// for hardware (adapter.c), data comes from : main/init, polling loop, entl_ait_sig_handler, and entl_error_sig_handler

// some amount of tcp data recieved (ugh - Nagle’s algorithm)
// I assume/trust that xmit boundaries apply ??
var receiveListener = function (data) {
    data = data.toString();
    var lines = data.split("\n");
    for (var i = 0, len = lines.length; i < len; i++) {
        var json_txt = lines[i];
        if (isBlank(json_txt)) continue;

        // frame arrived (json, see toJSON, toServer in adapter.c)
        try {
            // adapter - JSON : { machineName deviceName linkState entlState entlCount AITSent AITRecieved recvTime }
            var obj = JSON.parse(json_txt);
            if (obj == undefined) continue;

// backdoor mimics this:

            if (config.periodic) console.log( "entlCount:", obj.entlCount);

            // not checked against hostname
            if (!obj.machineName) continue;
            if (!obj.deviceName) continue;

            // ensure structure exists (multi-map)
            if (!json_data[obj.machineName]) { json_data[obj.machineName] = {}; }
            if (!last_state[obj.machineName]) { last_state[obj.machineName] = {}; }
            if (!last_msg[obj.machineName]) { last_msg[obj.machineName] = {}; }

            // hang onto line for debugging
            json_data[obj.machineName][obj.deviceName] = json_txt;

            var was_state = last_state[obj.machineName][obj.deviceName];
            last_state[obj.machineName][obj.deviceName] = obj.linkState;

            // I/O to spinner
            if (!connected) continue; // FIXME: nobody listening on socket yet?

            // inline rather than earthUpdate()
            io.emit('earth-update', json_txt);

            // ensure we log to console when the link state changes
            var toggled = !was_state || (was_state != obj.linkState);
            if (toggled || config.periodic) console.log('earth-update ' + json_txt);

            // recv state -> event logic

            var prev = last_msg[obj.machineName][obj.deviceName];
            last_msg[obj.machineName][obj.deviceName] = obj;

            if ((prev != undefined) && (obj.recvTime == prev.recvTime) && (obj.AITRecieved == prev.AITRecieved)) continue;

            // if (prev == undefined) { console.log('recv', 'READLOOP', obj.machineName, obj.deviceName, 'first time', obj); }
            // else if (obj.recvTime != prev.recvTime) { console.log('recv', 'READLOOP', obj.machineName, obj.deviceName, 'time diff', prev.recvTime, obj.recvTime); }
            // else if (obj.AITRecieved != prev.AITRecieved) { console.log('recv', 'READLOOP', obj.machineName, obj.deviceName, obj.recvTime, 'msg diff', prev.AITRecieved, obj.AITRecieved); }
            // else continue; // suppress duplication from polling loop

            if (config.trunc != 0) { console.log('recv', 'READLOOP', obj.recvTime, obj.AITRecieved, 'port:', obj.deviceName, 'hint:', hint(obj.deviceName)); }

            if (obj.AITRecieved == ' ') continue;

            noteDequeue(obj);
            echoServer(obj);
        } catch (e) {
            console.log('receiveListener', 'error: ' + e, 'raw:', json_txt);
        }
    }
};

var device2host = {
    "enp6s0" : "Alice",
    "enp8s0" : "Bob",
    "enp9s0" : "Carol",
    "enp7s0" : "Ted",
};
var device2slot = {
    "enp6s0" : 1,
    "enp8s0" : 2,
    "enp9s0" : 3,
    "enp7s0" : 4,
};
var slot2device = [ "enp6s0", "enp8s0", "enp9s0", "enp7s0" ];
var host2cell = {
    "Alice" : 0,
    "Bob" : 1,
    "Carol" : 2,
    "Ted" : 2,
};

/*
    phy enqueue Alice C:0 2 1550074879873183 "1550074879873183 Hello" ; http://localhost:3000/backdoor/enp8s0 status=200
    C1p1 C0p2 backward 1550074879873183 "1550074879873183 Hello"

    phy dequeue Alice C:0 2 1550074879899000 "1550074879873183 Hello" ; http://localhost:3000/backdoor/enp8s0 status=200
    C1p1 C0p2 backward 1550074879899000 "1550074879873183 Hello"
*/

// fudge things here:
// { AITRecieved, deviceName recvTime }
var noteDequeue = function(obj) {
    var recvTime = obj.recvTime;
    var msg_type = obj.AITRecieved;
    var deviceName = obj.deviceName;
    var port_index = device2slot[deviceName]; if (port_index == null) port_index = 100; // 'bogus';
    var url = 'http://localhost:' + s_port + '/backdoor/' + deviceName;

    // hardwired knowledge of demo config
    var recv_cell = host2cell[hostname]; if (recv_cell == null) recv_cell = 50; // 'bogus';
    var recv_port = port_index;
    var xmit_cell = recv_port - 1;
    var xmit_port = recv_cell + 1;
    var bias = (recv_cell > xmit_cell) ? 'forward' : 'backward';

    var recv_phy = 'C:' + recv_cell;
    var xmit_phy = 'C:' + xmit_cell;
    var dest = 'C' + recv_cell + 'p' + recv_port;
    var src = 'C' + xmit_cell + 'p' + xmit_port;
    console.log('   ', 'phy dequeue', hostname, recv_phy, port_index, recvTime, '"' + msg_type + '"', ';', url, 'status=200');
    console.log('   ', src, dest, bias, recvTime, '"' + msg_type + '"');
};

// fudge things here:
// { AITRecieved, deviceName }
var echoServer = function(obj) {
    var msg_type = obj.AITRecieved;
    var deviceName = obj.deviceName;

    if (msg_type == undefined) { console.log('echoServer DEBUG:', obj); return; }

    // UN-HACK
    // verb - ...
    // echoServer - JSON : { verb }
    var obj;
    try {
        obj = JSON.parse(msg_type);
    }
    catch (e) {
        // old simple msg goes thru this code path
        if (config.verbose) console.log('echoServer', 'error: ' + e, 'msg_type:', msg_type);
        return;
    }

    if (obj.verb != 'ECHO') { return; }

    obj.verb = 'RECHO';
    msg_type = JSON.stringify(obj);
    console.log('echoServer', msg_type);

    // fudge things here when route-repair:
    // jigger 'port' based upon routing table

    var tree = 'unknown'; // var o = JSON.parse(msg_type); var tree = o.tree;

    // mini routing table here
    var port = 0;

    var server_now = Date.now() * 1000.0; // server clock
    var port_index = device2slot[deviceName]; if (port_index == null) port_index = 100; // 'bogus';

    // hardwired knowledge of demo config
    var recv_cell = host2cell[hostname]; if (recv_cell == null) recv_cell = 50; // 'bogus';
    var recv_port = port_index;
    var xmit_cell = recv_port - 1;
    var xmit_port = recv_cell + 1;

    var recv_phy = 'C:' + recv_cell;
    var xmit_phy = 'C:' + xmit_cell;

    var frame = ''; // trust this works!
    var msg_id = 1; // trust this works!

    // log outbound (visualize)
    // cellAgentUpdate - JSON : { ait_code epoch frame msg_id msg_type outbound pe_id tree } # w/added nickname
    var neighbor_device = (xmit_port < slot2device.length) ? slot2device[recv_cell] : 'unknown'; // 'enp6s0'
    var nickname = hint(neighbor_device); // hostname for dest web server (eccf)
    var ca_msg = {
        'ait_code': 'NORMAL',
        'epoch': server_now,
        'frame': frame,
        'msg_id': msg_id,
        'msg_type': msg_type,
        'nickname': nickname,
        'outbound': recv_port,
        'pe_id': recv_phy,
        'tree': tree,
    };
    cellAgentUpdate(ca_msg);

    // automated response:
    // adapterWrite(deviceName, 'R' + msg_type);
    adapterWrite(deviceName, msg_type);
};

var connectionListener = function (socket) {
    c_socket = socket;
    var endpoint = socket.remoteAddress + ':' + socket.remotePort;
    console.log('net', c_port, 'connected from', endpoint);
    socket.on('data', receiveListener);
};

net.createServer(connectionListener).listen(c_port, '127.0.0.1');
