use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/working.pl' unless -x 't/cgi-bin/working.pl';

use Mojolicious::Lite;
plugin "CGI";
get
  "/cgi-bin/#script_name/*path_info" => {path_info => ''},
  sub {
  my $c      = shift;
  my $name   = $c->stash("script_name");
  my $script = File::Spec->rel2abs("t/cgi-bin/$name");
  $script = File::Spec->rel2abs("t/cgi-bin/$name.cgi") unless -x $script;
  $c->cgi->run(script => $script);
  };

my $t = Test::Mojo->new;

$t->get_ok('/cgi-bin/nope.cgi/foo')->status_is(500)->content_is("Could not run CGI script.\n");

$t->get_ok('/cgi-bin/env.cgi/some/path/info?query=123')->status_is(200)
  ->content_like(qr{^PATH_INFO=/some/path/info}m,               'PATH_INFO')
  ->content_like(qr{^QUERY_STRING=query=123}m,                  'QUERY_STRING')
  ->content_like(qr{^SCRIPT_FILENAME=\S+/t/cgi-bin/env\.cgi$}m, 'SCRIPT_FILENAME')
  ->content_like(qr{^SCRIPT_NAME=/cgi-bin/env\.cgi$}m,          'SCRIPT_NAME');

$t->get_ok('/cgi-bin/env/some/path/info?query=123')->status_is(200)
  ->content_like(qr{^PATH_INFO=/some/path/info}m,               'PATH_INFO')
  ->content_like(qr{^QUERY_STRING=query=123}m,                  'QUERY_STRING')
  ->content_like(qr{^SCRIPT_FILENAME=\S+/t/cgi-bin/env\.cgi$}m, 'SCRIPT_FILENAME')
  ->content_like(qr{^SCRIPT_NAME=/cgi-bin/env$}m,               'SCRIPT_NAME');

done_testing;
