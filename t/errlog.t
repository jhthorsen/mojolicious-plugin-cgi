use warnings;
use strict;
use Test::More;
use Test::Mojo;
use Mojolicious;

plan skip_all => 't/cgi-bin/errlog' unless -x 't/cgi-bin/errlog';

unlink 't/err.log';

{
  my $app = Mojolicious->new;
  my $t = Test::Mojo->new($app);
  my $s;

  $app->plugin(CGI => { route => '/err', script => 't/cgi-bin/errlog', errlog => 't/err.log' });

  $t->get_ok('/err');
  $s = -s 't/err.log';
  ok $s, 't/err.log has data';

  $t->get_ok('/err');
  ok -s 't/err.log' >= $s * 2, 't/err.log has more data';
}

unlink 't/err.log';
done_testing;
