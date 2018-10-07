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
my $port_map;
my $host_map;

if ( $#ARGV < 0 ) {
    print('usage: [-config='.$cfile.'] frames.json ...', $endl);
    exit -1
}

read_config($cfile); # default, lazy could have complext logic to avoid this

foreach my $fname (@ARGV) {
    if ($fname =~ /-config=/) { my ($a, $b) = split('=', $fname); read_config($b); next; }
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

        my $host = $o->{pe_id};
        my $port = $o->{outbound};
        print(join(' ', '   ', 'phy enqueue',
            # $host, $port,
            $o->{ait_code}, $o->{tree}, 'msg_id='.$o->{msg_id},
            substr($o->{frame}, 0, 10).'...',
            '; '
        ));
        my $url = api($host, $port);
        print($url, ' ');
        my $response = $ua->post_form($url, $o);
        print('status=', $response->{'status'}, $endl);
    }
}

sub read_config {
    my ($cfile) = @_;
    my @blueprint = inhale($cfile);
    my $config = decode_json(join($endl, @blueprint));
    $port_map = $config->{'ports'};
    $host_map = $config->{'hosts'};
}

sub api {
    my ($host, $port) = @_;
    my $ip_addr = $host_map->{$host};
    my $port_id = $port_map->[$port];
    my $url = 'http://'.$ip_addr.':3000/port/'.$port_id;
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

# my $ct = 'application/json; charset=utf-8';
# my $response = $ua->post($url, Content_Type => $ct, Content => $data);

