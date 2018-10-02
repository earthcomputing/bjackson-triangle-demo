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

# --

my $endl = "\n";
my $dquot = '"';
my $blank = ' ';

# --

my $port_id = 'enp6s0';
my $url = 'http://localhost:3000/port/'.$port_id;

#phy enqueue C:1 1 TOCK 0x400074367c704351baf6176ffc4e1b6a msg_id=1835423081272486972 7b226d7367... ;
my $cell_id = 'C:1';
my $token = 'TOCK';
my $tree_id = 0xc4e1b6a;
my $frame = '7b226d7367...';

my $data = {
    cell_id => $cell_id,
    port_id => $port_id,
    token => $token,
    tree_id => $tree_id,
    frame => $frame
};

my $ua = HTTP::Tiny->new;
my $response = $ua->post_form($url, $data);
print($response->{'status'}, $endl);

# my $response = $ua->post($url, $data);
# my $ct = 'application/json; charset=utf-8'; # 'form-data'
# my $response = $ua->post($url, Content_Type => $ct, Content => $data);
