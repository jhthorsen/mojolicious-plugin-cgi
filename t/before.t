use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/working.pl' unless -x 't/cgi-bin/working.pl';

{
  use Mojolicious::Lite;
  plugin CGI => {
    route => '/user/:id',
    script => 't/cgi-bin/env.cgi',
    before => sub {
      my $c = shift;
      my $query = $c->req->url->query;
      
      $query->param(id => $c->stash('id'));
      $query->param(other_value => 123);
    },
  };
}

my $t = Test::Mojo->new;

$t->get_ok('/user/42')
  ->status_is(200)
  ->content_like(qr{^QUERY_STRING=id=42}m, 'QUERY_STRING=id=42')
  ->content_like(qr{^QUERY_STRING=.*other_value=123}m, 'QUERY_STRING=...other_value=123')
  ;

done_testing;
