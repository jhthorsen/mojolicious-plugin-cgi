use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/redirect.pl' unless -x 't/cgi-bin/redirect.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/redirect' => 't/cgi-bin/redirect.pl' ];
}

my $t = Test::Mojo->new;

$t->get_ok('/redirect', {} )
  ->status_is(302)
  ->header_is('Location' => 'http://somewhereelse.com')
  ->content_is('');

done_testing;
