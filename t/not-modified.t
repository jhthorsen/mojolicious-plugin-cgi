use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/not-modified.pl' unless -x 't/cgi-bin/not-modified.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/not-modified' => 't/cgi-bin/not-modified.pl' ];
}

my $t = Test::Mojo->new;

$t->get_ok('/not-modified' => {'If-None-Match' => 'ABC'})
    ->status_is(304)
    ->header_is('X-Test' => 'if-none-match seen: ABC');

done_testing;
