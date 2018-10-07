
const s_port = 3000;
const c_port = 1337;

const cell_ui = 'cell-ui.html';

if (process.argv.length <= 2) {
    console.log("Usage:", __filename, "hostname");
    process.exit(-1);
}
 
const hostname = process.argv[2];
console.log('hostname:', hostname);

var last_ait = {};
var json_data = {};
var connected = 0;
var c_socket;

var config = {
    "trunc" : -30,
    "verbose" : false
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
    if (config.verbose) console.log('port ...', req.method, req.url, req.params);
    next();
})

app.post('/port/:port_id', function (req, res) {
    cellAgentUpdate(req.body);
    var frame = req.body.frame;
    req.body.frame = null;
    if (config.verbose) console.log('POST port ...',
        '\nheaders:', req.headers,
        '\nbody:', req.body
    );
    var host = req.body.pe_id;
    var port = req.params.port_id;
    if (config.trunc != 0) { console.log('POST port:', port, 'frame:', frame.substr(config.trunc)); }
    adapterWrite(port, frame);
    res.send('POST port ...' + JSON.stringify(req.params));
});

function adapterWrite(port, message) {
    last_ait[port] = message;
    c_socket.write('{ \"port\": \"' + port + '\", \"message\":\"' + message + '\" }')
}

// cellagent-update
function cellAgentUpdate(d) {
    if (config.verbose) console.log('cellagent-update:', d);
    io.emit('cellagent-update', d);
}

app.get('/port/:port_id', function (req, res) {
    if (config.verbose) console.log('GET port ...', req.params);
    var message = last_ait[req.params.port_id];
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
    var endpoint = socket.id; // socket.remoteAddress + ':' + socket.remotePort;
    console.log('io connected from', endpoint);
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

// update function for earth-connect update
function earthUpdate(socket, data) {
    console.log(data);
    io.emit("earth-update", data);
}

function isBlank(str) {
    return (!str || /^\s*$/.test(str));
}

var receiveListener = function (data) {
    data = data.toString();
    var jd = data.split("\n");
    for (var i = 0, len = jd.length; i < len; i++) {
        var d = jd[i];
        if (isBlank(d)) continue;

        try {
            var obj = JSON.parse(d);
            if (!obj) continue;

            console.log( "entlCount:", obj.entlCount);

            // not checked against hostname
            if (!obj.machineName) continue;
            json_data[obj.machineName] = d;

            // I/O to spinner
            if (!connected) continue;
            io.emit('earth-update', d);
            console.log('earth-update ' + d);
        } catch(e) {
            console.log('error:' + e);
        }
    }
};

var connectionListener = function (socket) {
    c_socket = socket;
    var endpoint = socket.remoteAddress + ':' + socket.remotePort;
    console.log('Client connected from', endpoint);
    socket.on('data', receiveListener);
};

net.createServer(connectionListener).listen(c_port, '127.0.0.1');
