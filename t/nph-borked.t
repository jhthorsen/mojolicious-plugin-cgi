use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/nph-borked.pl' unless -x 't/cgi-bin/nph-borked.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/nph-borked' => 't/cgi-bin/nph-borked.pl' ];
}

my $t = Test::Mojo->new;

$t->get_ok('/nph-borked', {} )
  ->status_is(403)
  ->content_like(qr'This is the borked paywall');

done_testing;
