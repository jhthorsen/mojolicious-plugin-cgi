use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/not-found.pl' unless -x 't/cgi-bin/not-found.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/not-found' => 't/cgi-bin/not-found.pl' ];
}

my $t = Test::Mojo->new;

$t->get_ok('/not-found', {} )
  ->status_is(404)
  ->content_like(qr'This page is missing');

done_testing;
