use Mojo::Base -strict;

use Test::More;

use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use File::Which;
use FindBin;

use IO::Socket::INET;
use Mojo::IOLoop::Server;
use Mojo::Server::Hypnotoad;
use Mojo::UserAgent;
use Mojo::Util qw(slurp spurt);

# Prepare script
my $dir = tempdir CLEANUP => 1;
my $script = catfile $dir, 'myapp.pl';
my $port  = Mojo::IOLoop::Server->generate_port;

spurt <<EOF, $script;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;

plugin Config => {
  default => {
    hypnotoad => {
      inactivity_timeout => 3,
      listen => ['http://127.0.0.1:$port'],
      workers => 4
    }
  }
};

plugin CGI => {
  route => '/',
  run => sub {
    print "HTTP/1.1 200 OK\r\n";
    print "Content-Type: text/text; charset=ISO-8859-1\r\n";
    print "\r\n";
    print "Hello CGI!\n";
  },
};

app->start;
EOF

# Start server
my $hypnotoad = which 'hypnotoad';
open my $start, '-|', $^X, $hypnotoad, $script;
sleep 1 while !_port($port);

# Remember PID
open my $file, '<', catfile($dir, 'hypnotoad.pid');
my $pid = <$file>;
chomp $pid;
ok $pid, "PID $pid found";

# Application is alive
my $ua = Mojo::UserAgent->new;
my $tx = $ua->get("http://127.0.0.1:$port/");
is $tx->res->code, 200, 'right status';
is $tx->res->body, "Hello CGI!\n", 'right content';

# Hammer the server
my $delay = Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    for my $i (1 .. 100) {
      $ua->get("http://127.0.0.1:$port/" => $delay->begin);
    };
  }
)->wait();

# Stop the server
open my $stop, '-|', $^X, $hypnotoad, $script, '-s';
sleep 1 while _port($port);

# Checking Processes
my $alive = kill 0 => $pid;
is $alive, 0, "$pid is terminated";

sub _port { IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => shift) }

done_testing();
