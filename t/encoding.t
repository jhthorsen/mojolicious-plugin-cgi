use t::Helper;
use utf8; # source file contains utf8 encoded string literals

use Mojolicious::Lite;
plugin CGI => {route => '/env/basic', script => cgi_script('env.cgi')};

my $t = Test::Mojo->new;

# when printing the test name, avoid "wide character in print"

$t->get_ok('/env/basic/f%C3%B6%C3%B6')
  ->content_like(qr{^PATH_INFO=/föö}m, 'PATH_INFO=/foo with umlaut');

$t->get_ok('/env/basic/foo%e2%80%99s')
  ->content_like(qr{^PATH_INFO=/foo’s}m, 'PATH_INFO=/foo with apostrophe');

done_testing;
