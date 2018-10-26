#!/usr/local/bin/perl -w
#!/usr/bin/perl -w
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

# JSON : { pe_id, outbound, ait_code, tree, msg_id, frame }
# phy enqueue C:1 1 TOCK 0x400074367c704351baf6176ffc4e1b6a msg_id=1835423081272486972 7b226d7367... ;
sub process_file {
    my ($path) = @_;
    my $gzip = $path =~ m/.gz$/;
    my $openspec = ($gzip) ?  'gunzip -c '.$path.'|' : '<'.$path;
    open(FD, $openspec) or die $path.': '.$!;
    while (<FD>) {
        my $json_text = $_;
        my $o = decode_json($json_text);

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
        sleep($delay) if $delay;
    }
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

