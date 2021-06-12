#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
#---------------------------------------------------------------------------------------------
 #  Copyright © 2016-present Earth Computing Corporation. All rights reserved.
 #  Licensed under the MIT License. See LICENSE.txt in the project root for license information.
#---------------------------------------------------------------------------------------------
# python -mjson.tool

use 5.010;
use strict;
use warnings;

use lib '/Users/bjackson/perl5/lib/perl5';
use JSON qw(decode_json encode_json);
use Data::Dumper;
use Digest::SHA qw(sha1_hex);
use Data::GUID;

use HTTP::Tiny;

my $ua = HTTP::Tiny->new;

# --

my $endl = "\n";
my $dquot = '"';
my $blank = ' ';

$|++; # autoflush

# --

my $cfile = 'blueprint-triangle.json';
my $delay = 0;
my $channel_map;
my $port_map;
my $cell_map;
my $nicknames;

if ( $#ARGV < 0 ) {
    print('usage: [-config='.$cfile.'] [-delay=secs] frames.json ...', $endl);
    exit -1
}

read_config($cfile); # default, lazy could have complext logic to avoid this

foreach my $fname (@ARGV) {
    if ($fname =~ /-config=/) { my ($a, $b) = split('=', $fname); read_config($b); next; }
    if ($fname =~ /-delay=/) { my ($a, $b) = split('=', $fname); $delay=$b; next; }
    process_file($fname);
}

# packet-seq - JSON : { ait_code epoch frame msg_id msg_type outbound pe_id tree } # w/added nickname
# phy enqueue C:1 1 TOCK 0x400074367c704351baf6176ffc4e1b6a msg_id=1835423081272486972 7b226d7367... ;
sub process_file {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    while (<FD>) {
        my $json_text = $_;
        my $o = decode_json($json_text);

        # bogus records - workaround for analyzer bug
        unless (defined $o->{outbound}) {
            print(join(' ', 'BAD RECORD', $o->{epoch}, $o->{pe_id}, 'null', $o->{tree}, $o->{msg_type}), $endl);
            $o->{outbound} = -1;
            next;
        }

        # embed verb + clean-payload into msg_type
        my $fo = pe_process($o);
        if (defined $fo) {
            $o->{msg_type} = JSON->new->canonical->encode($fo);
        }

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

        # POST to /port
        print($url, ' ');
        my $response = $ua->post_form($url, $o);
        print('status=', $response->{'status'}, $endl);
        sleep($delay) if $delay;
    }
}

## deserialize / unravel:
sub pe_process {
    my ($pe_op) = @_;

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

    if ($msg_type eq 'Hello') {
        # payload: cell_id port_no
        my ($cname, $cguid) = parts($payload->{cell_id});
        my $nick = $nicknames->{$cname}; $nick = '' unless defined $nick;
        # Hello - JSON : { verb nickname guid sector }
        my $o = {
            'verb' => $msg_type,
            'nickname' => $nick,
            'guid' => $cguid,
            'sector' => $payload->{port_no}
        };
        return $o;
    }

    if ($msg_type eq 'Discover') {
        # payload : gvm_eqn hops path sending_cell_id tree_id
        # Discover - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    if ($msg_type eq 'DiscoverD') {
        # payload : path senging_cell_id tree_id
        # DiscoverD - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    if ($msg_type eq 'Manifest') {
        # payload : deploy_tree_id manifest tree_name
        # Manifest - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    if ($msg_type eq 'StackTree') {
        # payload : allowed_tree gvm_eqn new_tree_id parent_tree_id
        # StackTree - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    if ($msg_type eq 'StackTreeD') {
        # payload : tree_id
        # StackTreeD - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    if ($msg_type eq 'Application') {
        # payload : body tree_id
        # Application - JSON : { verb }
        my $o = {
            'verb' => $msg_type
        };
        return $o;
    }

    shape($msg_type, $payload, '');
    return undef;
}

sub parts {
    my ($ref) = @_;
    return ($ref->{name}, $ref->{uuid}{uuid});
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

sub inhale {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    my @body = <FD>;
    close(FD);
    return @body;
}

## map (c1, p1) -> (c2, p2) -> (c1, pX) -> (c2, pY)
## match (cA, cB) 1 -> X ; 2 -> Y
sub remap {
    my ($c1, $p1, $c2, $p2) = @_;
}

# my $ct = 'application/json; charset=utf-8';
# my $response = $ua->post($url, Content_Type => $ct, Content => $data);

