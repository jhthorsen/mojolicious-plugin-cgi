use warnings;
use strict;
use Test::More;
use Test::Mojo;

my @pipes = get_pipes();

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

if ($pid) {
  ok !(kill 0, $pid), 'child is taken care of';
}
else {
  ok 0, 'could not get pid from cgi output';
}

is_deeply \@pipes, [get_pipes()], 'no leaky leaks';

sub get_pipes {
  return diag "unable to test leaky pipes", 1 unless -d "/proc/$$/fd";
  return diag "test for leaky pipes under Debian build", 1 if $ENV{DEBIAN_BUILD};

  my @pipes;
  for my $fd (glob "/proc/$$/fd/*") {
    my $pts = readlink sprintf '/proc/%s/fd/%s', $$, +(split '/', $fd)[-1] or next;
    push @pipes, $pts if $pts =~ /pipe:/;
  }

  return sort @pipes;
}

done_testing;
