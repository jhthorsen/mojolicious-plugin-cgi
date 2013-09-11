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
    {file => 't/test_file_with_a_long_filename.txt'},
  ]}
);
$t->status_is(200);
$t->content_like(qr{^\d+\n--- Content-Type: .*?Content-Type: .*?Content-Type: }s);
# multi line Content-Disposition header should be collapsed into one line
$t->content_like(qr{Content-Disposition: form-data; name="mytext"; filename="test_file_with_a_long_filename\.txt"}s);

done_testing;
