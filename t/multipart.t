use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/file_upload' unless -x 't/cgi-bin/file_upload';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/file_upload' => 't/cgi-bin/file_upload' ];
}

my $t = Test::Mojo->new;

$t->post_ok(
  '/file_upload' => form => {mytext => [
    {file => 't/foo.txt'},
    {file => 't/bar.txt'},
  ]}
)
  ->status_is(200)
  ->content_like(qr{^\d+\n--- Content-Type: .*?Content-Type: .*?Content-Type: }s);

done_testing;
