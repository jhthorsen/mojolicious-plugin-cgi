use utf8;
use t::Helper;
use Mojo::Base -strict;
use Test::More;
use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop::Server;
use Mojo::UserAgent;
use Mojo::Util 'spurt';
use Encode qw(decode_utf8);

plan skip_all => $@
  unless -e '.git' and eval 'require require File::Which && 1';

# Prepare script
my $dir = tempdir CLEANUP => 1;
my $script = catfile $dir, 'myapp.pl';
my $port = Mojo::IOLoop::Server->generate_port;

spurt <<EOF, $script;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;
use Encode qw(decode_utf8);

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port'],
      workers => 2
    }
  }
};

plugin CGI => {
  route => '/',
  run => sub {
    print "HTTP/1.1 200 OK\r\n";
    print "Content-Type: text/plain; charset=UTF-8\r\n";
    print "\r\n";
    my \$path_info = decode_utf8(\$ENV{PATH_INFO});
    binmode(STDOUT, ":encoding(UTF-8)");
    print "\$path_info\n";
  },
};

app->start;
EOF

# Start server
my $hypnotoad = File::Which::which('hypnotoad');
open my $start, '-|', $^X, $hypnotoad, $script;
sleep 1 while !_port($port);

# Remember PID
open my $file, '<', catfile($dir, 'hypnotoad.pid');
my $pid = <$file>;
chomp $pid;
ok $pid, "PID $pid found";

# Application is alive
my $ua = Mojo::UserAgent->new;
my $tx = $ua->get("http://127.0.0.1:$port/foo");
is $tx->res->code, 200,            'right status';
is $tx->res->body, "/foo\n",        'right content';

# This is what we want to test!
is decode_utf8($ua->get("http://127.0.0.1:$port/föö")->res->body),
    "/föö\n", 'with umlauts';
is decode_utf8($ua->get("http://127.0.0.1:$port/fö’")->res->body),
    "/fö’\n", 'with quote';

# Stop the server
open my $stop, '-|', $^X, $hypnotoad, $script, '-s';
sleep 1 while _port($port);

# Checking Processes
my $alive = kill 0 => $pid;
is $alive, 0, "$pid is terminated";

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing();
