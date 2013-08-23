use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/postman' unless -x 't/cgi-bin/postman';

{
  use Mojolicious::Lite;
  plugin CGI => [ '/postman' => 't/cgi-bin/postman' ];
}

my $t = Test::Mojo->new;

$t->post_ok('/postman', {}, "some\ndata\n")
  ->status_is(200)
  ->content_like(qr{^\d+\n--- some\n--- data\n$});

my $pid = $t->tx->res->body =~ /(\d+)/ ? $1 : 0;

diag $pid;

if($pid) {
  ok !(kill 0, $pid), 'child is taken care of';
}
else {
  ok $pid, 'could not get pid';
}

# FIXME? possibly not the best way to test if there is a pipe leak
if (-d "/proc/$$/fd") {
  my $pipes = grep { defined $_ ? /pipe:/ : undef }
    map { readlink("/proc/$$/fd/".(split '/')[-1]) }
      glob "/proc/$$/fd/*";

  note "pipes:$pipes";
  ok( !($pipes % 2),'no leaky pipes');
}

done_testing;
