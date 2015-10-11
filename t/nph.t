use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/nph.pl' unless -x 't/cgi-bin/nph.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/nph' => 't/cgi-bin/nph.pl' ];
}

my $t = Test::Mojo->new;

$t->get_ok('/nph', {} )
  ->status_is(403)
  ->content_like(qr'This is the paywall');

done_testing;
