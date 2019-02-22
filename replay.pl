#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
# python -mjson.tool
# replay.pl -config=blueprint-sim.json -delay=1 -status=status.json -routes=routes.json

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
    if ($fname =~ /-status=/) { my ($a, $b) = split('=', $fname); process_file('status', $b); next; }
    if ($fname =~ /-routes=/) { my ($a, $b) = split('=', $fname); process_file('routes', $b); next; }
    process_file('frames', $fname);
}

sub process_file {
    my ($kind, $path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    while (<FD>) {
        my $json_text = $_;
        my $o = decode_json($json_text);
        my $epoch = $o->{epoch};
        my $pe_id = $o->{pe_id};

        my $nick = $nicknames->{$pe_id}; $nick = '' unless defined $nick;
        $o->{nickname} = $nick;

        do_frame($epoch, $pe_id, $o) if $kind eq 'frames';
        do_status($epoch, $pe_id, $o) if $kind eq 'status';
        do_routes($epoch, $pe_id, $o) if $kind eq 'routes';
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

# --

# packet-seq - JSON : { ait_code epoch frame msg_id msg_type outbound pe_id tree } # w/added nickname
# phy enqueue C:1 1 TOCK 0x400074367c704351baf6176ffc4e1b6a msg_id=1835423081272486972 7b226d7367... ;
sub do_frame {
    my ($epoch, $pe_id, $o) = @_;
    my $port = $o->{outbound};
    my $url = port_api($pe_id, $port);

    # bogus records - workaround for analyzer bug
    unless (defined $o->{outbound}) {
        print(join(' ', 'BAD RECORD', $epoch, $pe_id, 'null', $o->{tree}, $o->{msg_type}), $endl);
        $o->{outbound} = -1;
        next;
    }

    # embed verb + clean-payload into msg_type
    my $fo = pe_process($o);
    if (defined $fo) {
        $o->{msg_type} = JSON->new->canonical->encode($fo);
    }

    print(join(' ', '   ', 'phy enqueue',
        $o->{nickname}, $pe_id, $port,
        $o->{ait_code}, $o->{tree}, $o->{msg_type}, 'msg_id='.$o->{msg_id},
        substr($o->{frame}, 0, 10).'...',
        '; '
    ));

    unless (defined $url) {
        print($endl, join(' ', 'skipping -', $o->{nickname}, 'pe_id:', $pe_id, 'port:', $port), $endl);
        next;
    }

    # POST to /port
    print($url, ' ');
    my $response = $ua->post_form($url, $o);
    print('status=', $response->{'status'}, $endl);
}

# {"epoch":1539644788261202,"pe_id":"C:0","uuid":"400044de-7a1d-45bf-9a50-f68d23fe64ab","port_no":1,"is_border":false,"status":"Connected"}
# status - JSON : { epoch pe_id uuid port_no is_border status }
sub do_status {
    my ($epoch, $pe_id, $o) = @_;
    my $port = $o->{port_no};
    my $url = status_api($pe_id, $port);

    unless (defined $url) {
        print($endl, join(' ', 'skipping -', $o->{nickname}, 'pe_id:', $pe_id, 'port:', $port), $endl);
        next;
    }

    # POST to /port
    print($url, ' ');
    my $response = $ua->post_form($url, $o);
    print('status=', $response->{'status'}, $endl);
}

# {"pe_id":"C:0","epoch":1539644788259902,"op":"create","tree":"4000d881-b3e5-458a-857f-dd86e335bdc2","in_use":true,"may_send":true,"parent":0,"mask":"0000000000000001"}
# routes - JSON : { epoch pe_id op tree in_use may_send parent mask }
sub do_routes {
    my ($epoch, $pe_id, $o) = @_;
    my $tree = $o->{tree};
    my $url = route_api($pe_id, $tree);

    unless (defined $url) {
        print($endl, join(' ', 'skipping -', $o->{nickname}, 'pe_id:', $pe_id, 'tree:', $tree), $endl);
        next;
    }

    # POST to /port
    print($url, ' ');
    my $response = $ua->post_form($url, $o);
    print('status=', $response->{'status'}, $endl);
}

sub port_api {
    my ($pe_id, $port) = @_;
    my $ip_endpoint = $cell_map->{$pe_id};
    return undef unless defined $ip_endpoint;
    return undef if $port > @{$port_map};

    my $port_id = $port_map->[$port - 1]; # adjust index, 0 is cell-agent
    my $url = 'http://'.$ip_endpoint.'/port/'.$port_id;
    return $url;
}

sub status_api {
    my ($pe_id, $port) = @_;
    my $ip_endpoint = $cell_map->{$pe_id};
    return undef unless defined $ip_endpoint;
    return undef if $port > @{$port_map};

    my $port_id = $port_map->[$port - 1]; # adjust index, 0 is cell-agent
    my $url = 'http://'.$ip_endpoint.'/ifconfig/'.$port_id;
    return $url;
}

sub route_api {
    my ($pe_id, $tree) = @_;
    my $ip_endpoint = $cell_map->{$pe_id};
    return undef unless defined $ip_endpoint;

    my $url = 'http://'.$ip_endpoint.'/route/'.$tree;
    return $url;
}

