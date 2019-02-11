
const cell_ui = 'cell-ui.html';

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
var last_state = {};
var json_data = {};
var alt_route = {};
var connected = 0;
var c_socket;

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
app.post('/backdoor/:port_id', function (req, res) {
    var port = req.params.port_id;
    backdoorUpdate(req.body);
    if (config.verbose) console.log('POST backdoor ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

// FIXME : crossing streams here - 

    var machineName = req.body.nickname;
    var pe_id = req.body.pe_id;
    var inbound = req.body.inbound;
    var xmit_now = req.body.xmit_now;
    var msg_type = req.body.msg_type;

    if (config.trunc != 0) { console.log('POST', xmit_now, msg_type, 'port:', port); }

    var obj = {
        AITMessage : msg_type,
        deviceName : port
    };

    echoServer(obj);

    // previous state:
    // json_data[obj.machineName][obj.deviceName] = json_txt;

    res.send('POST backdoor ...' + JSON.stringify(req.params));
});

app.post('/route/:port_id', function (req, res) {
    var port = req.params.port_id;
    // routeUpdate(req.body);
    if (config.verbose) console.log('POST route ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );

    var redirect = req.body.alt_route;
    if (config.trunc != 0) { console.log('POST', 'route', 'port:', port, 'redirect', redirect); }

    alt_route[port] = redirect;
    res.send('POST route ...' + JSON.stringify(req.params));
});

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
    if (config.trunc != 0) { console.log('POST', msg_type, 'port:', port, 'frame:', frame.substr(config.trunc)); }

    // fudge things here when route-repair:
    if (msg_type.slice(0, 4) == 'ECHO') {
        // jigger 'port' based upon routing table
    }

    adapterWrite(port, msg_type);
    res.send('POST port ...' + JSON.stringify(req.params));
});

function adapterWrite(port, message) {
    last_ait[port] = message;
    c_socket.write('{ \"port\": \"' + port + '\", \"message\":\"' + message + '\" }')
}

// backdoor-update - share with visualizers:
function backdoorUpdate(d) {
    if (config.verbose) console.log('backdoor-update:', d);
    io.emit('backdoor-update', d); // earth-update
}

// cellagent-update - share with visualizers
function cellAgentUpdate(d) {
    if (config.verbose) console.log('cellagent-update:', d);
    io.emit('cellagent-update', d);
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

var data = {
    "deviceName" : "enp6s0",
    "linkState" : "UP",
    "entlState" : "HELLO",
    "entlCount" : "990",
    "AITMessage" : "-none-"
};

// earth-update - share with visualizers
function earthUpdate(data) {
    if (config.verbose) console.log(data);
    io.emit("earth-update", data);
}

function isBlank(str) {
    return (!str || /^\s*$/.test(str));
}

var receiveListener = function (data) {
    data = data.toString();
    var lines = data.split("\n");
    for (var i = 0, len = lines.length; i < len; i++) {
        var json_txt = lines[i];
        if (isBlank(json_txt)) continue;

        // frame arrived
        try {
            var obj = JSON.parse(json_txt);
            if (!obj) continue;

// backdoor mimics this:

            if (config.periodic) console.log( "entlCount:", obj.entlCount);

            // not checked against hostname
            if (!obj.machineName) continue;
            if (!obj.deviceName) continue;

            if (!json_data[obj.machineName]) { json_data[obj.machineName] = {}; }
            json_data[obj.machineName][obj.deviceName] = json_txt;

            if (!last_state[obj.machineName]) { last_state[obj.machineName] = {}; }
            var was_state = last_state[obj.machineName][obj.deviceName];
            var toggled = !was_state || (was_state != obj.linkState);
            last_state[obj.machineName][obj.deviceName] = obj.linkState;

            // I/O to spinner
            if (!connected) continue;

            // inline rather than earthUpdate()
            io.emit('earth-update', json_txt);
            if (toggled || config.periodic) console.log('earth-update ' + json_txt);

            echoServer(obj);
        } catch(e) {
            console.log('error:' + e);
        }
    }
};

// fudge things here:
// { AITMessage, deviceName }
var echoServer = function(obj) {
    var msg_type = obj.AITMessage;
    var deviceName = obj.deviceName;

    if (msg_type.slice(0, 4) != 'ECHO') { return; }

console.log('echo', 'from', deviceName);

    // fudge things here when route-repair:
    // jigger 'port' based upon routing table

    // mini routing table here
    var port = 0;

    // automated response:
    adapterWrite(deviceName, 'R' + msg_type);
};

var connectionListener = function (socket) {
    c_socket = socket;
    var endpoint = socket.remoteAddress + ':' + socket.remotePort;
    console.log('net', c_port, 'connected from', endpoint);
    socket.on('data', receiveListener);
};

net.createServer(connectionListener).listen(c_port, '127.0.0.1');
