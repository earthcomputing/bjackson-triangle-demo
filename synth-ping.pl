#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------
# synth-ping.pl -config=blueprint-sim.json -machine=Ted -delay=0 -n=5

use 5.010;
use strict;
use warnings;

use lib '/Users/bjackson/perl5/lib/perl5';
use JSON qw(decode_json encode_json);
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Data::GUID;

use Time::HiRes qw(gettimeofday);
use HTTP::Tiny;

my $ua = HTTP::Tiny->new;

# --

my $endl = "\n";
my $dquot = '"';
my $blank = ' ';

my $machine_name;
my $delay = 1;

my $cfile;
$cfile = 'blueprint-sim.json';
$cfile = 'blueprint-triangle.json';

my $NPACKET = 10;

read_config($cfile);

foreach my $arg (@ARGV) {
    if ($arg =~ /-config=/) { my ($a, $b) = split('=', $arg); read_config($b); next; }
    if ($arg =~ /-machine=/) { my ($a, $b) = split('=', $arg); $machine_name=$b; next; }
    if ($arg =~ /-n=/) { my ($a, $b) = split('=', $arg); $NPACKET=$b; next; }
    if ($arg =~ /-delay=/) { my ($a, $b) = split('=', $arg); $delay=$b; next; }
    # process_file($arg);
}

# --

my $msg_type = 'ECHO';

my $root_cell_code = 'C:2';
my $epoch = '1539644788363461';
my $msg_id = '171641756590852295';
my $guid = '0x4000e4c0929a46ad82438ab8b0629b5d';
my $sender_name = 'Sender:'.$root_cell_code.'+VM:'.$root_cell_code.'+vm1';
my $sender_guid = '4000f220-14da-494e-9b17-a28d3a93e4b6';
my $p_tree_name = $root_cell_code.'+NocMasterAgent';
my $p_tree_guid = '4000e4c0-929a-46ad-8243-8ab8b0629b5d';
my $sender_id = build_id($sender_name, $sender_guid);
my $p_tree_id = build_id($p_tree_name, $p_tree_guid);

my $template_op = decode_json('{
    "ait_code": "NORMAL",
    "epoch": "'.$epoch.'",
    "frame": "",
    "msg_id": "'.$msg_id.'",
    "msg_type": "ECHO",
    "outbound": "2",
    "pe_id": "'.$root_cell_code.'",
    "tree": "'.$guid.'"
}');

my $template_frame = decode_json('{
    "msg_type": "'.$msg_type.'",
    "serialized_msg": ""
}');

my $template_msg = decode_json('{
"header": {
    "direction": "Leafward",
    "is_ait": false,
    "msg_count": 25,
    "msg_type": "'.$msg_type.'",
    "sender_id": { "name": "'.$sender_name.'", "uuid": { "uuid": "'.$sender_guid.'" }},
    "tree_map": {}
},
"payload": {
    "body": [],
    "tree_id": { "name": "'.$p_tree_name.'", "uuid": { "uuid": "'.$p_tree_guid.'" }}
}
}');

echo_task();
exit 0;

# --

sub build_id {
    my ($name, $dash_guid) = @_;
    my $id_obj = { name => $name, uuid => { uuid => $dash_guid } };
    # my $id = JSON->new->canonical->encode($id_obj);
    return $id_obj;
}

## when msg_type is 'Application' - payload :

# frameseq : lines of json-text : { ait_code epoch msg_id msg_type outbound pe_id tree - frame }
# $pe_op->{frame} : hex-coded json-text : { msg_type - serialized_msg }
# $frame->{serialized_msg} : json-text : { header payload }
## $serialized_msg->{header} : { msg_count is_ait tree_map msg_type sender_id direction }
## $serialized_msg->{payload} : { tree_id - body }
# $payload->{body} : array[u8]-coded text

sub echo_task {
    my $dash_guid = '4000e4c0-929a-46ad-8243-8ab8b0629b5d';
    my $id = 1;
    my $seq_no = 1;
    foreach my $seq_no (1..$NPACKET) {
        my $line = echo_op($dash_guid, $id, $seq_no);
        my $pe_op = decode_json($line);
        xmit_packet($pe_op);
        sleep($delay) if $delay;
    }
}

# --

sub process_file {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    while (<FD>) {
        my $json_text = $_;
        my $pe_op = decode_json($json_text);
        pe_process($pe_op);
    }
}

sub pe_process {
    my ($pe_op) = @_;
    # print(Dumper $pe_op, $endl);

    # 2 bogus records
    unless (defined $pe_op->{outbound}) {
        print(join(' ', 'BAD RECORD', $pe_op->{epoch}, $pe_op->{pe_id}, 'null', $pe_op->{tree}, $pe_op->{msg_type}), $endl);
        $pe_op->{outbound} = -1;
    }

    print(join(' ', $pe_op->{epoch}, $pe_op->{pe_id}, $pe_op->{outbound}, $pe_op->{tree}, $pe_op->{msg_type}), $endl);
    # $pe_op->{msg_id} % 1000, 

# filter
    return if $pe_op->{msg_type} eq 'TCP'; # workaround for bug in analyzer

## deserialize / unravel:

    my $raw_frame = $pe_op->{frame};
    # print($raw_frame, $endl);

    my $frame = frame2obj($raw_frame);
    # return unless defined $frame;
    # print(Dumper $frame, $endl);

    my $raw_msg = $frame->{serialized_msg};
    # $raw_msg =~ s/^"//; $raw_msg =~ s/"$//;
    my $msg = decode_json($raw_msg);
    # return unless defined $msg;
    # print(Dumper $msg, $endl);

    my $hdr = $msg->{header};
    my $payload = $msg->{payload};
    # return unless defined $hdr;
    # return unless defined $payload;
    # print(Dumper $hdr, $endl);
    # print(Dumper $payload, $endl);

    my $msg_type = $hdr->{msg_type};
    # return unless defined $msg_type;
    # print($msg_type, $endl);

    # print(join(' ', $pe_op->{msg_type}, $frame->{msg_type}, $hdr->{msg_type}), $endl);
    # print(join(' ', '    TREE', $pe_op->{tree}, $payload->{tree_id}{uuid}{uuid}, $payload->{tree_id}{name}), $endl) if defined $payload->{tree_id};

    # sanity checking:
    shape($msg_type, $pe_op, 'ait_code epoch frame msg_id msg_type outbound pe_id tree');
    shape($msg_type, $frame, 'msg_type serialized_msg');
    shape($msg_type, $msg, 'header payload');
    shape($msg_type, $hdr, 'direction is_ait msg_count msg_type sender_id tree_map');
    # shape($msg_type, $payload, 'body tree_id'); # only for 'Application'

    # print(Dumper $pe_op, $endl);
    # print(Dumper $frame, $endl);
    # print(Dumper $msg, $endl);
    # print(Dumper $hdr, $endl);
    # print(Dumper $payload, $endl);

    # seems like only Manifest has a non-empty tree_map ??
    ## my $tree_map = $hdr->{tree_map};
    ## print(join(' ', '    tree_map:', sort keys $tree_map), $endl) if keys $tree_map;

# filter
    return unless $msg_type eq 'Application';

    my $raw_body = $payload->{body};
    # return unless defined $raw_body;
    # print($raw_body, $endl);
    my $blk = bytes2dense($raw_body); # u8 to hex-coded
    # return unless defined $blk;
    # print($blk, $endl);
    my $body = pack('H*', $blk); # hex_to_ascii
    print('## ', $body, $endl);

# return;

# --

## re-serialize / pack:

    my $text_update = 'ECHO { tree: "4000e4c0-929a-46ad-8243-8ab8b0629b5d" id: 1, seq_no: 25 }';

    $body = $text_update;
    my $u8 = dense2bytes($body); #  same as $raw_body
    $payload->{body} = $u8;
    $msg->{payload} = $payload;
    $raw_msg = JSON->new->canonical->encode($msg);
    $frame->{serialized_msg} = $raw_msg;
    my $new_frame = JSON->new->canonical->encode($frame);
    $raw_frame = str2hex($new_frame);
    $pe_op->{frame} = $raw_frame;

my $DEBUG = undef;
if ($DEBUG) {
    print(Dumper $pe_op, $endl);
    print(Dumper $frame, $endl);
    print(Dumper $msg, $endl);
    print(Dumper $hdr, $endl);
    print(Dumper $payload, $endl);

    # print(Dumper $u8, $endl);
    # print($new_frame, $endl);
}

    my $line = JSON->new->canonical->encode($pe_op);
    print($line, $endl);

    print($new_frame, $endl);
    print($raw_msg, $endl);
}

# --

sub echo_op {
    my ($dash_guid, $id, $seq_no) = @_;
    my $hex_guid = '0x'.$dash_guid; $hex_guid =~ s/-//g;

    my ($sec, $usec) = gettimeofday();
    my $epoch  = ($sec * 1000 * 1000) + $usec; # '1539644788363461';

    my $msg_id = '171641756590852295';

    my $echo_payload = {
        verb => 'ECHO',
        tree => $dash_guid,
        id => $id,
        seqno => $seq_no
    };

    my $text_update = JSON->new->canonical->encode($echo_payload);
    my $line = build_line($epoch, $msg_id, $hex_guid, $text_update);
    # print($line, $endl);
    return $line;
}

# syntheize things for post-frame.pl
sub build_line {
    my ($epoch, $msg_id, $hex_guid, $body) = @_;

    my $pe_op = $template_op;
    my $frame = $template_frame;
    my $msg = $template_msg;

    ## update pe_op : { ait_code epoch msg_id msg_type outbound pe_id tree - frame }
    # $pe_op->{ait_code} = $ait_code; # 'NORMAL'
    # $pe_op->{msg_type} = $msg_type; # 'ECHO'
    # $pe_op->{outbound} = $outbound; # '2'
    # $pe_op->{pe_id} = $pe_id; 'C:2'
    $pe_op->{epoch} = $epoch;
    $pe_op->{msg_id} = $msg_id;
    $pe_op->{tree} = $hex_guid;

    my $hdr = $msg->{header};
    my $payload = $msg->{payload};

## update header : { msg_count is_ait tree_map msg_type sender_id direction }
## update payload : { tree_id - body }
    # my $msg_count = $hdr->{msg_count}; # 25
    # my $is_ait = $hdr->{is_ait}; # false
    # my $tree_map = $hdr->{tree_map}; # {}
    # my $sender_id = $hdr->{sender_id}; ## sender_id
    # my $direction = $hdr->{direction}; # 'Leafward'
    my $msg_type = $hdr->{msg_type};

    # $payload->{tree_id} = $tree_id; ## p_tree_id
    my $raw_body = dense2bytes($body); #  same as $raw_body
    $payload->{body} = $raw_body;

    $msg->{payload} = $hdr;
    $msg->{payload} = $payload;
    my $raw_msg = JSON->new->canonical->encode($msg);
    $frame->{serialized_msg} = $raw_msg;

    my $new_frame = JSON->new->canonical->encode($frame);
    my $raw_frame = str2hex($new_frame);
    $pe_op->{frame} = $raw_frame;

### HACK!!!

$pe_op->{msg_type} = $body;

    my $line = JSON->new->canonical->encode($pe_op);
    return $line;
}
# --

sub inhale {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    my @body = <FD>;
    close(FD);
    return @body;
}

my $channel_map;
my $port_map;
my $cell_map;
my $nicknames;

sub read_config {
    my ($cfile) = @_;
    my @blueprint = inhale($cfile);
    my $config = decode_json(join($endl, @blueprint));
    $channel_map = $config->{'channel_map'};
    $port_map = $config->{'ports'};
    $cell_map = $config->{'cells'};
    $nicknames = $config->{'nicknames'};
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

sub xmit_packet {
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

sub shape {
    my ($msg_type, $ref, $expect) = @_;
    my $keyset = join(' ', sort keys %{$ref});
    return if $keyset eq $expect;
    print(join(' ', $msg_type, ':', 'mismatch', $expect, '-', $keyset), $endl);
}

sub frame2obj {
    my ($frame) = @_;
    my $json_text = pack('H*', $frame); # hex_to_ascii
    my $o = decode_json($json_text);
    # print($json_text, $endl);
    return $o;
}

sub bytes2dense {
    my ($u8) = @_;
    my $dense = '';
    foreach my $ch (@{$u8}) {
        my $doublet = sprintf('%02x', $ch);
        $dense = $dense.$doublet;
    }
    # print($dense, $endl);
    return $dense;
}

sub dense2bytes {
    my ($s) = @_;
    my @cary = split(//, $s); # unpack('H2', $s);
    my @u8 = map { ord } @cary;
    return \@u8;
}

sub str2hex {
    my ($s) = @_;
    my @cary = split(//, $s);
    my $dense = '';
    foreach my $ch (@cary) {
        my $doublet = sprintf('%02x', ord($ch));
        $dense = $dense.$doublet;
    }
    # print($dense, $endl);
    return $dense;
}

# --

my $notes = << '_eof_';

# gzcat ten-1540532887547934/frames.json.gz | encode-mock.pl | grep ##

## Hello From Master
## Reply from Container:VM:C:3+vm1+2
## Reply from Container:VM:C:4+vm1+2
## Hello From Master
## Hello From Master
## Reply from Container:VM:C:7+vm1+2
## Reply from Container:VM:C:7+vm1+2
## Hello From Master
## Hello From Master
## Hello From Master
## Reply from Container:VM:C:0+vm1+2
## Reply from Container:VM:C:1+vm1+2

--

pe_op : { ait_code epoch msg_id msg_type outbound pe_id tree - frame }
*frame : { msg_type - serialized_msg }
*serialized_msg : { header payload }
header : { msg_count is_ait tree_map msg_type sender_id direction }
payload : { tree_id - body }
*body : text

# tree - string "0x..."
# is_ait - boolean
# sender_id - guid(name, uuid.uuid)
# tree_map - obj {}
# tree_id - guid(name, uuid.uuid)

# --

other payloads:

    Hello : cell_id port_no
    Discover : gvm_eqn hops path sending_cell_id tree_id
    DiscoverD : path senging_cell_id tree_id
    Failover : broken_tree_ids lw_port_tree_id path rw_port_tree_id
    Manifest : deploy_tree_id manifest tree_name
    StackTree : allowed_tree gvm_eqn new_tree_id parent_tree_id
    StackTreeD : tree_id

_eof_
