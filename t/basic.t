use warnings;
use strict;
use Test::More;
use Test::Mojo;

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

$t->get_ok('/env/basic?query=123')
  ->status_is(200)
  ->content_like(qr{ENVIRONMENT
CONTENT_LENGTH=0
CONTENT_TYPE=
GATEWAY_INTERFACE=CGI/1\.1
HTTPS=NO
HTTP_COOKIE=
HTTP_HOST=localhost:\w+
HTTP_REFERER=
HTTP_USER_AGENT=Mojolicious \(Perl\)
PATH=/env/basic
PATH_INFO=/env/basic
QUERY_STRING=query=123
REMOTE_ADDR=\d+\S+
REMOTE_HOST=localhost
REMOTE_PORT=\w+
REMOTE_USER=
REQUEST_METHOD=GET
SCRIPT_FILENAME=\S+/t/cgi-bin/env\.cgi
SCRIPT_NAME=env/basic
SERVER_ADMIN=\w+
SERVER_NAME=\w+
SERVER_PORT=\d+
SERVER_PROTOCOL=HTTP
SERVER_SOFTWARE=Mojolicious::Plugin::CGI
});

done_testing;
