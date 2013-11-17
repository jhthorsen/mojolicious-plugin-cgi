package Mojolicious::Plugin::CGI;

=head1 NAME

Mojolicious::Plugin::CGI - Run CGI script from Mojolicious

=head1 VERSION

0.07

=head1 DESCRIPTION

This plugin enable L<Mojolicious> to run Perl CGI scripts. It does so by forking
a new process with a modified environment and reads the STDOUT in a non-blocking
matter.

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin CGI => [ '/script' => '/path/to/cgi/script.pl' ];
  plugin CGI => {
    route => '/mount/point',
    script => '/path/to/cgi/script.pl',
    env => {}, # default is \%ENV
    errlog => '/path/to/file.log', # path to where STDERR from cgi script goes
    before => sub { # called before setup and script start
      my $c = shift;
      # modify QUERY_STRING
      $c->req->url->query->param(a => 123);
    },
  };

  app->start;

=cut

use Mojo::Base 'Mojolicious::Plugin';
use File::Basename;
use File::Spec;
use Sys::Hostname;
use POSIX ':sys_wait_h';
use Socket;
use constant CHUNK_SIZE => 131072;
use constant CHECK_CHILD_INTERVAL => $ENV{CHECK_CHILD_INTERVAL} || 0.01;
use constant DEBUG => $ENV{MOJO_PLUGIN_CGI_DEBUG} || 0;

our $VERSION = '0.07';
our %ORIGINAL_ENV = %ENV;

=head1 METHODS

=head2 env

Returns a hash ref containing the environment variables that should be
used when starting the CGI script. Defaults to C<%ENV> when this module
was loaded.

=cut

has env => sub { +{ %ORIGINAL_ENV } };

=head2 emulate_environment

  %env = $self->emulate_environment($c);

Returns a hash which contains the environment variables which should be used
by the CGI script.

In addition to L</env>, these dynamic variables are set:

  CONTENT_LENGTH, CONTENT_TYPE, HTTP_COOKIE, HTTP_HOST, HTTP_REFERER,
  HTTP_USER_AGENT, HTTPS, PATH, PATH_INFO, QUERY_STRING, REMOTE_ADDR,
  REMOTE_HOST, REMOTE_PORT, REMOTE_USER, REQUEST_METHOD, SCRIPT_NAME,
  SERVER_PORT, SERVER_PROTOCOL.

Additional static variables:

  GATEWAY_INTERFACE = "CGI/1.1"
  SERVER_ADMIN = $ENV{USER}
  SCRIPT_FILENAME = Script name given as argument to register.
  SERVER_NAME = Sys::Hostname::hostname()
  SERVER_SOFTWARE = "Mojolicious::Plugin::CGI"

=cut

sub emulate_environment {
  my($self, $c) = @_;
  my $tx = $c->tx;
  my $req = $tx->req;
  my $headers = $req->headers;
  my $remote_user = '';

  if(my $userinfo = $c->req->url->to_abs->userinfo) {
    $remote_user = $userinfo =~ /([^:]+)/ ? $1 : '';
  }
  elsif($c->session('username')) {
    $remote_user = $c->session('username');
  }

  my $content_length = $req->content->is_multipart
    ? $req->body_size : $headers->content_length;

  return(
    %{ $self->env },
    CONTENT_LENGTH => $content_length || 0,
    CONTENT_TYPE => $headers->content_type || '',
    GATEWAY_INTERFACE => 'CGI/1.1',
    HTTP_COOKIE => $headers->cookie || '',
    HTTP_HOST => $headers->host || '',
    HTTP_REFERER => $headers->referrer || '',
    HTTP_USER_AGENT => $headers->user_agent || '',
    HTTPS => $req->is_secure ? 'YES' : 'NO',
    #PATH => $req->url->path,
    PATH_INFO => '/' .($c->stash('path_info') || ''),
    QUERY_STRING => $req->url->query->to_string,
    REMOTE_ADDR => $tx->remote_address,
    REMOTE_HOST => gethostbyaddr(inet_aton($tx->remote_address || '127.0.0.1'), AF_INET) || '',
    REMOTE_PORT => $tx->remote_port,
    REMOTE_USER => $remote_user,
    REQUEST_METHOD => $req->method,
    SCRIPT_FILENAME => $self->{script},
    SCRIPT_NAME => $self->{route}->render(''),
    SERVER_ADMIN => $ENV{USER} || '',
    SERVER_NAME => hostname,
    SERVER_PORT => $tx->local_port,
    SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP', # TODO: Version is missing
    SERVER_SOFTWARE => __PACKAGE__,
  );
}

=head2 register

  $self->register($app, [ $route => $script ]);
  $self->register($app, %args);
  $self->register($app, \%args);

C<route> and L<path> need to exist as keys in C<%args> unless given as plain
arguments.

C<$route> can be either a plain path or a route object.

=cut

sub register {
  my($self, $app, $args) = @_;
  my $log = $app->log;
  my $got_log_file = $log->path ? 1 : 0;
  my($cb, $before);

  if(ref $args eq 'ARRAY') {
    $self->{route} = shift @$args;
    $self->{script} = shift @$args;
  }
  else {
    $self->{$_} ||= $args->{$_} for keys %$args;
  }

  $before = $self->{before} || sub {};

  $self->{script} = File::Spec->rel2abs($self->{script});
  -r $self->{script} or die "Cannot read $self->{script}";
  $self->{name} = basename $self->{script};
  $self->{route} = $app->routes->any("$self->{route}/*path_info", { path_info => '' }) unless ref $self->{route};
  $self->{prefix_length} = length $self->{route}->render('');
  $self->{route}->to(cb => sub {
    my $c = shift->render_later;
    my $ioloop = Mojo::IOLoop->singleton;
    my $reactor = $ioloop->reactor;
    my $stdin;
    my $delay = $ioloop->delay;
    my($pid, $tid, $reader, $stdout_read, $stdout_write);

    $log->debug("Running $self->{script} ...");

    unless(pipe $stdout_read, $stdout_write) {
      return $c->render_exception("pipe: $!");
    }
    if ($c->req->content->is_multipart) {
      $stdin = Mojo::Asset::File->new;
      $stdin->add_chunk($c->req->build_body);
    } else {
      $stdin = $c->req->content->asset;
    }

    unless($stdin->isa('Mojo::Asset::File')) {
      warn "Converting $stdin to Mojo::Asset::File\n" if DEBUG;
      $stdin = Mojo::Asset::File->new->add_chunk($stdin->slurp);
    }

    $reader = $self->_stdout_callback($c, $stdout_read);
    $reactor->io($stdout_read, $reader);
    $reactor->watch($stdout_read, 1, 0);
    $c->$before;

    unless(defined($pid = fork)) {
      return $c->render_exception("fork: $!");
    }
    unless($pid) {
      warn "[$$] Starting child process\n" if DEBUG;
      %ENV = $self->emulate_environment($c);
      close $stdout_read;
      open STDIN, '<', $stdin->path or die "Could not open @{[$stdin->path]}: $!" if -s $stdin->path;
      open STDOUT, '>&' . fileno $stdout_write or die $!;
      open STDERR, '>>', $self->{errlog} if $self->{errlog};
      select STDOUT;
      $| = 1;
      { exec $self->{script} }
      die "Could not execute $self->{script}: $!";
    }

    warn "[$pid] Resuming parent process\n" if DEBUG;
    $tid = $ioloop->recurring(CHECK_CHILD_INTERVAL, sub {
      waitpid $pid, WNOHANG or return;
      warn "[$pid] Child ended\n" if DEBUG;
      $reader->();
      $reactor->watch($stdout_read, 0, 0);
      $reactor->remove($stdout_read);
      $reactor->remove($tid);
      unlink $c->stash('cgi.stdin')->path;
      $c->stash('cgi.cb')->();
      warn "[$pid] Finishing up\n" if DEBUG;
      $c->finish;
    });

    $c->stash('cgi.pid' => $pid, 'cgi.stdin' => $stdin, 'cgi.cb' => $delay->begin);
    $delay->wait unless $ioloop->is_running;
  });
}

sub _stdout_callback {
  my($self, $c, $stdout_read) = @_;
  my $buf = '';
  my $headers;

  return sub {
    my $read = $stdout_read->sysread(my $b, CHUNK_SIZE, 0) or return;
    warn "[@{[$c->{stash}{'cgi.pid'}]}] ($!) <<< ($b)\n" if DEBUG;

    if($headers) {
      return $c->write($b);
    }

    $buf .= $b;
    $buf =~ s/^(.*?\x0a\x0d?\x0a\x0d?)//s or return;
    $headers = $1;

    if($headers =~ /^HTTP/) {
      $c->res->parse($headers);
    }
    else {
      $c->res->code($headers =~ /Location:/ ? 302 : 200);
      $c->res->parse($c->res->get_start_line_chunk(0) .$headers);
    }

    $c->write($buf) if length $buf;
  }
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
