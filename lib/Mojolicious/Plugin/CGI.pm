package Mojolicious::Plugin::CGI;

=head1 NAME

Mojolicious::Plugin::CGI - Run CGI script from Mojolicious

=head1 VERSION

0.0401

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
use POSIX qw/ :sys_wait_h /;
use Sys::Hostname;
use Socket;
use constant CHUNK_SIZE => 131072;

our $VERSION = '0.0401';
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
  my $base_path = $req->url->base->path;
  my $script_name = $req->url->path;

  $script_name =~ s!^/?\Q$base_path\E/?!!;

  return(
    %{ $self->env },
    CONTENT_LENGTH => $headers->content_length || 0,
    CONTENT_TYPE => $headers->content_type || '',
    GATEWAY_INTERFACE => 'CGI/1.1',
    HTTP_COOKIE => $headers->cookie || '',
    HTTP_HOST => $headers->host || '',
    HTTP_REFERER => $headers->referrer || '',
    HTTP_USER_AGENT => $headers->user_agent || '',
    HTTPS => $req->is_secure ? 'YES' : 'NO',
    #PATH => $req->url->path,
    PATH_INFO => $req->url->path,
    QUERY_STRING => $req->url->query->to_string,
    REMOTE_ADDR => $tx->remote_address,
    REMOTE_HOST => gethostbyaddr(inet_aton($tx->remote_address), AF_INET) || '',
    REMOTE_PORT => $tx->remote_port,
    REMOTE_USER => $c->session('username') || '', # TODO: Should probably be configurable
    REQUEST_METHOD => $req->method,
    SCRIPT_FILENAME => $self->{script},
    SCRIPT_NAME => $script_name,
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
  $self->{route} = $app->routes->any($self->{route}) unless ref $self->{route};
  $self->{route}->to(cb => sub {
    my $c = shift->render_later;
    my $reactor = Mojo::IOLoop->singleton->reactor;
    my $stdin = $c->req->content->asset;
    my $delay = Mojo::IOLoop->delay;
    my($pid, $stdout_read, $stdout_write);

    $log->debug("Running $self->{script} ...");

    unless(pipe $stdout_read, $stdout_write) {
      return $c->render_exception("pipe: $!");
    }
    unless($c->req->content->isa('Mojo::Content::Single')) {
      return $c->render_exception('Can only handle Mojo::Content::Single requests');
    }
    unless($stdin->isa('Mojo::Asset::File')) {
      $stdin = Mojo::Asset::File->new->add_chunk($stdin->slurp);
    }

    $reactor->io($stdout_read, $self->_stdout_callback($c, $stdout_read));
    $reactor->watch($stdout_read, 1, 0);
    $c->$before;

    unless(defined($pid = fork)) {
      return $c->render_exception("fork: $!");
    }
    unless($pid) {
      %ENV = $self->emulate_environment($c);
      close $stdout_read;
      open STDIN, '<', $stdin->path or die "Could not open @{[$stdin->file]}: $!";
      open STDOUT, '>&' . fileno $stdout_write or die $!;
      select STDOUT;
      $| = 1;
      { exec $self->{script} }
      die "Coudl not execute $self->{script}: $!";
    }

    $c->stash('cgi.pid' => $pid, 'cgi.stdin' => $stdin, 'cgi.cb' => $delay->begin);
    $delay->wait unless Mojo::IOLoop->is_running;
  });
}

sub _stdout_callback {
  my($self, $c, $stdout_read) = @_;
  my $buf = '';
  my $headers;

  return sub {
    my $read = $stdout_read->sysread(my $b, CHUNK_SIZE, 0);

    if(!$read) {
      Mojo::IOLoop->singleton->reactor->remove($stdout_read);
      $c->stash('cgi.stdin')->handle->close;
      unlink $c->stash('cgi.stdin')->path;
      waitpid $c->stash('cgi.pid'), 0;
      $c->stash('cgi.cb')->();
      return $c->finish;
    }
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

1;
