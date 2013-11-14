use warnings;
use strict;
use Test::More;
use Test::Mojo;

plan skip_all => 't/cgi-bin/errlog' unless -x 't/cgi-bin/errlog';

{
  use Mojolicious::Lite;
  plugin CGI => {
    route => '/err',
    script => 't/cgi-bin/errlog',
    errlog => 't/err.log',
  };
}

my $t = Test::Mojo->new;
my $s;
unlink 't/err.log';

{
  $t->get_ok('/err');
  $s = -s 't/err.log';
  ok $s, 't/err.log has data';

  $t->get_ok('/err');
  ok -s 't/err.log' >= $s * 2, 't/err.log has more data';
}

unlink 't/err.log';
done_testing;
