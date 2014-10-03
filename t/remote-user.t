use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/working.pl' unless -x 't/cgi-bin/working.pl';

{
  use Mojolicious::Lite;
  plugin CGI => {route => '/auth', script => 't/cgi-bin/env.cgi', env => {}};
}

my $t = Test::Mojo->new;

$t->get_ok('/auth')->status_is(200)->status_is(200)->content_like(qr{^REMOTE_USER=}m, 'REMOTE_USER=');

$t->get_ok($t->tx->req->url->clone->userinfo('Aladdin:foopass'), {'Authorization' => ''})->status_is(200)
  ->content_like(qr{^REMOTE_USER=Aladdin$}m, 'REMOTE_USER=Aladdin');

$t->get_ok($t->tx->req->url->clone->userinfo('whatever:foopass'),
  {'Authorization' => 'Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ=='})->status_is(200)
  ->content_like(qr{^REMOTE_USER=Aladdin$}m, 'REMOTE_USER=Aladdin');


done_testing;
