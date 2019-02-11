#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
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

$|++; # autoflush

# --

my $cfile = 'blueprint-sim.json';
my $machine_name = 'Alice';

my $channel_map;
my $port_map;
my $cell_map;
my $nicknames;

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

sub process_arg {
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

sub read_loop {
    my ($csock) = @_;
    my $cell = cell_id($machine_name);

    my $data = '';
    while (1) {
        my $buf = <$csock>; # $csock->recv($buf, 1024);
        # print(Dumper($buf), $endl);
        return unless $buf;
        chomp($buf);
        print($buf, $endl);
        $data .= $buf;

        my $json;
        eval { $json = decode_json($data); };
        next unless defined $json;
        $data = '';

        my ($sec, $usec) = gettimeofday();
        my $now  = ($sec * 1000 * 1000) + $usec;

# --

        my $port_id = $json->{port};
        my $msg = $json->{message};
        my $port = invert_port($port_id);
        my $cid = $cell; $cid =~ s/C://;
        my $link = 'C'.$cid.'p'.($port+1);
        my $dest = $channel_map->{$link};

        next unless $dest =~ m/C(\d)p(\d)/;
        my ($n_cell, $n_port) = ($1, $2);
        # my $n_sock = $cell_map->{'C:'.$n_cell};
        my $url = api('C:'.$n_cell, $n_port);

        my $o = '';

        print(join(' ', $cell, $port, $link, $dest, $n_cell, $n_port, $url, $now, $msg), $endl);

        $data = $now." ok".$endl;
        $csock->send($data);
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
    foreach my $i (0 .. @{$port_map}) {
        return $i if $port_id eq $port_map->[$i];
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
    my $url = 'http://'.$ip_endpoint.'/port/'.$port_id;
    return $url;
}

sub cross_read {
    my ($o) = @_;
    my $cell_id = $o->{pe_id};
    my $port = $o->{outbound};
    my $nick = $nicknames->{$cell_id}; $nick = '' unless defined $nick;
    $o->{nickname} = $nick;
    print(join(' ', '   ', 'phy enqueue',
        $o->{nickname}, $cell_id, $port,
        $o->{ait_code}, $o->{tree}, $o->{msg_type}, 'msg_id='.$o->{msg_id},
        substr($o->{frame}, 0, 10).'...',
        '; '
    ));

    my $url = api($cell_id, $port);
    unless (defined $url) {
        print($endl, join(' ', 'skipping -', $nick, 'cell:', $cell_id, 'port:', $port), $endl);
        next;
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
phy enqueue Carol C:2 2 NORMAL 0x4000e4c0929a46ad82438ab8b0629b5d Application msg_id=171641756590852295 7b226d7367... ; http://localhost:3002/port/enp8s0 status=200

# server:
POST Application port: enp8s0 frame: 303632396235645c227d7d7d7d227d

# adapter:
{ "port": "enp8s0", "message":"Application" }

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
