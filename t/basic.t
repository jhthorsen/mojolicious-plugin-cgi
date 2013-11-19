use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/working.pl' unless -x 't/cgi-bin/working.pl';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/working' => 't/cgi-bin/working.pl' ];
  plugin CGI => { route => '/env/basic', script => 't/cgi-bin/env.cgi', env => {} };
}

my $t = Test::Mojo->new;

$t->get_ok('/working')
  ->status_is(200)
  ->header_is('Content-Type' => 'text/custom')
  ->content_is("basic stuff\n");

$t->get_ok($t->tx->req->url->clone->userinfo('testdummy:foopass')->path('/env/basic/foo')->query(query => 123))
  ->status_is(200)
  ->content_like(qr{^ENVIRONMENT}m, 'ENVIRONMENT')
  ->content_like(qr{^CONTENT_LENGTH=0}m, 'CONTENT_LENGTH=0')
  ->content_like(qr{^CONTENT_TYPE=}m, 'CONTENT_TYPE=')
  ->content_like(qr{^GATEWAY_INTERFACE=CGI/1\.1}m, 'GATEWAY_INTERFACE=CGI/1\.1')
  ->content_like(qr{^HTTPS=NO}m, 'HTTPS=NO')
  ->content_like(qr{^HTTP_COOKIE=}m, 'HTTP_COOKIE=')
  ->content_like(qr{^HTTP_HOST=localhost:\d+}m, 'HTTP_HOST=localhost:\d+')
  ->content_like(qr{^HTTP_REFERER=}m, 'HTTP_REFERER=')
  ->content_like(qr{^HTTP_USER_AGENT=Mojolicious \(Perl\)}m, 'HTTP_USER_AGENT=Mojolicious \(Perl\)')
  ->content_like(qr{^PATH_INFO=/foo}m, 'PATH_INFO=/env/basic')
  ->content_like(qr{^QUERY_STRING=query=123}m, 'QUERY_STRING=query=123')
  ->content_like(qr{^REMOTE_ADDR=\d+\S+}m, 'REMOTE_ADDR=\d+\S+')
  ->content_like(qr{^REMOTE_HOST=[\w\.]+}m, 'REMOTE_HOST=')
  ->content_like(qr{^REMOTE_PORT=\w+}m, 'REMOTE_PORT=\w+')
  ->content_like(qr{^REMOTE_USER=testdummy}m, 'REMOTE_USER=testdummy')
  ->content_like(qr{^REQUEST_METHOD=GET}m, 'REQUEST_METHOD=GET')
  ->content_like(qr{^SCRIPT_FILENAME=\S+/t/cgi-bin/env\.cgi}m, 'SCRIPT_FILENAME=\S+/t/cgi-bin/env\.cgi')
  ->content_like(qr{^SCRIPT_NAME=/env/basic}m, 'SCRIPT_NAME=env/basic')
  ->content_like(qr{^SERVER_ADMIN=\w+}m, 'SERVER_ADMIN=\w+')
  ->content_like(qr{^SERVER_NAME=\w+}m, 'SERVER_NAME=\w+')
  ->content_like(qr{^SERVER_PORT=\d+}m, 'SERVER_PORT=\d+')
  ->content_like(qr{^SERVER_PROTOCOL=HTTP}m, 'SERVER_PROTOCOL=HTTP')
  ->content_like(qr{^SERVER_SOFTWARE=Mojolicious::Plugin::CGI}m, 'SERVER_SOFTWARE=Mojolicious::Plugin::CGI')
  ;

done_testing;
