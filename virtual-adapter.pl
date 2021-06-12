#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------
# python -mjson.tool

# virtual-adapter.pl localhost:1337
# blueprint-sim.json

use 5.010;
use strict;
use warnings;

use lib '/Users/bjackson/perl5/lib/perl5';
use JSON qw(decode_json encode_json);
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Data::GUID;

use IO::Socket::INET;
use HTTP::Tiny;
use Time::HiRes qw(gettimeofday);

my $ua = HTTP::Tiny->new;


# --

my $endl = "\n";
my $dquot = '"';
my $blank = ' ';
my $leading = '   ';

$|++; # autoflush

# --

my $cfile = 'blueprint-sim.json';
my $machine_name = 'Alice';

my $channel_map;
my $port_map;
my $cell_map;
my $nicknames;

my $DEBUG; # = 1;

if ( $#ARGV < 0 ) {
    print('usage: [-config='.$cfile.'] [-machine='.$machine_name.']] <hostname:port>', $endl);
    exit -1
}

read_config($cfile); # default, lazy could have complext logic to avoid this

foreach my $arg (@ARGV) {
    if ($arg =~ /-config=/) { my ($a, $b) = split('=', $arg); read_config($b); next; }
    if ($arg =~ /-machine=/) { my ($a, $b) = split('=', $arg); $machine_name=$b; next; }
    process_arg($arg);
}

sub process_arg_server {
    my ($arg) = @_;
    my ($host, $port) = split(':', $arg);

    # creating a listening socket
    my $socket = new IO::Socket::INET (
        LocalHost => $host,
        LocalPort => $port,
        Proto => 'tcp',
        Listen => 5,
        Reuse => 1
    );

    die 'cannot create socket'.$! unless $socket;
    print(join(' ', 'waiting on port', $port), $endl);

    while(1) {
        my $csock = $socket->accept();
        my $c_address = $csock->peerhost();
        my $c_port = $csock->peerport();
        print(join(' ', 'connection from', $c_address.':'.$c_port), $endl);
        read_loop($csock);
        shutdown($csock, 1);
        print(join(' ', 'closed', $c_address.':'.$c_port), $endl);
    }
    $socket->close();
}

sub process_arg {
    my ($arg) = @_;
    my ($host, $port) = split(':', $arg);

    my $socket = new IO::Socket::INET (
        PeerHost => $host,
        PeerPort => $port,
        Proto => 'tcp'
    );

    die 'cannot create socket'.$! unless $socket;
    my $c_address = $socket->sockaddr();
    my $c_port = $socket->sockport();
    print(join(' ', 'connection from', $c_address.':'.$c_port), $endl);
    print(join(' ', 'connection to', $arg), $endl);

    ## $socket->disable_timeout; ## DANGER!
    read_loop($socket);
}

sub read_loop {
    my ($csock) = @_;
    my $cell = cell_id($machine_name);

    print(join(' ', 'emulating phy', $machine_name, $cell), $endl);

    my $data = '';
    while ($csock->connected()) {
        my $buf = '';
        # my $buf = <$csock>;
        $csock->recv($buf, 1024);
        # print(Dumper($buf), $endl);
        return unless defined $csock->connected(); # might be much, much later
        return unless $buf;
        chomp($buf);
        print($buf, $endl) if $buf;
        $data .= $buf;

        # huh ??
        next if $data eq '';

        my $json;
        eval { $json = decode_json($data); };
        print('ERROR: bad decode='.$data, $endl) unless defined $json;
        next unless defined $json;
        $data = '';

        ## adapter clock:
        my ($sec, $usec) = gettimeofday();
        my $adapter_now  = ($sec * 1000 * 1000) + $usec;

# --

## FIXME : ensure 'message' is json !!

        my $port_id = $json->{port};
        my $msg = $json->{message}; # $adapter_now.' '.
        print(join(' ', 'DEBUG:', $port_id, $msg, $dquot.$data.$dquot, Dumper $json), $endl) if $DEBUG;

        my $port = invert_port($port_id);
        my $cid = $cell; $cid =~ s/C://;
        my $endpoint = 'C'.$cid.'p'.($port+1);
        my ($dest, $bias) = find_chan($endpoint);
        print(join(' ', 'DEBUG:', $port, $cid, $endpoint, $dest, $bias), $endl) unless defined $dest;
        print(join(' ', 'DEBUG:', $port, $cid, $endpoint, $dest, $bias), $endl) if $DEBUG;

        print('ERROR: dest='.$dest, $endl) unless $dest =~ m/C(\d)p(\d)/;
        next unless $dest =~ m/C(\d)p(\d)/;
        my ($n_cell, $n_port) = ($1, $2);
        my $pe_id = 'C:'.$n_cell;
        my $nick = $nicknames->{$pe_id};
        my $n_sock = $cell_map->{$pe_id};
        my $url = api($pe_id, $n_port);
        print(join(' ', 'DEBUG:', $n_cell, $n_port, $pe_id, $nick, $n_sock, $url), $endl) if $DEBUG;

        my $o = {
            pe_id => $pe_id,
            inbound => $n_port,
            machineName => $nick,
            xmitTime => $adapter_now,
            msg_type => $msg
        };
        cross_read($o);

        print(join(' ', $leading, $endpoint, $dest, $bias, $adapter_now, $dquot.$msg.$dquot), $endl);

        # my $hdx = $adapter_now." ok".$endl;
        # $csock->send($hdx); ## when debugging - echo input
    }
}

sub cell_id {
    my ($machine_name) = @_;
    foreach my $k (keys %{$nicknames}) {
        my $value = $nicknames->{$k};
        return $k if $value eq $machine_name;
    }
}

sub invert_port {
    my ($port_id) = @_;
    foreach my $i (0..@{$port_map}) {
        my $value = $port_map->[$i];
        return $i if $port_id eq $value;
    }
    print(join(' ', 'DEBUG', 'invert_port', 'not found:', $port_id), $endl);
    return undef;
}

sub find_chan {
    my ($endpoint) = @_;
    my $fw = $channel_map->{$endpoint};
    return ($fw, 'forward')  if defined $fw;

    foreach my $k (keys %{$channel_map}) {
        my $bw = $channel_map->{$k};
        return ($k, 'backward') if $bw eq $endpoint
    }
    return undef;
}

sub read_config {
    my ($cfile) = @_;
    my @blueprint = inhale($cfile);
    my $config = decode_json(join($endl, @blueprint));

    $channel_map = $config->{'channels'};
    $port_map = $config->{'ports'};
    $cell_map = $config->{'cells'};
    $nicknames = $config->{'nicknames'};
}

sub inhale {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    my @body = <FD>;
    close(FD);
    return @body;
}

# FIXME : port_map must agree with blueprint!
# { 1: 'enp6s0', 2: 'enp8s0', 3: 'enp9s0', 4: 'enp7s0' }
sub api {
    my ($cell_id, $port) = @_;
    my $ip_endpoint = $cell_map->{$cell_id};
    return undef unless defined $ip_endpoint;
    return undef if $port > @{$port_map};

    my $port_id = $port_map->[$port - 1]; # adjust index, 0 is cell-agent
    my $url = 'http://'.$ip_endpoint.'/backdoor/'.$port_id;
    return $url;
}

sub cross_read {
    my ($o) = @_;
    my $cell_id = $o->{pe_id};
    my $port = $o->{inbound};
    my $nick = $nicknames->{$cell_id}; $nick = '' unless defined $nick;
    # $o->{nickname} = $nick;

    print(join(' ', $leading, 'phy enqueue',
        $nick , $cell_id, $port,
        # $o->{xmitTime}, 
        $dquot.$o->{msg_type}.$dquot,
        '; '
    ));

    my $url = api($cell_id, $port);
    unless (defined $url) {
        print($endl, join(' ', 'skipping -', $nick, 'cell:', $cell_id, 'port:', $port), $endl);
        return;
    }
    print($url, ' ');
    my $response = $ua->post_form($url, $o);
    print('status=', $response->{'status'}, $endl);
}

# --

my $notes = << '_eof_';

    inet_ntoa($hostname);

    syslog(LOG_INFO, "Server Address: Machine Name: %s\n", argv[1]);
    machine_name = argv[1];

    my $json_text = $_;
    my $o = decode_json($json_text);

# --

# poster:
# Carol server:
# Carol adapter:
# Bob server (backdoor):
# Bob adapter:
# Carol server:

# --

{
    "ports": [ "enp6s0", "enp8s0", "enp9s0", "enp7s0" ],
    "cells": {
        "C:0": "localhost:3000",
        "C:1": "localhost:3001",
        "C:2": "localhost:3002"
    },
    "nicknames": {
        "C:0": "Alice",
        "C:1": "Bob",
        "C:2": "Carol",
    },
    "channels": {
        "C0p2":"C1p1",
        "C0p3":"C2p1",
        "C1p3":"C2p2",
    },
}

_eof_
