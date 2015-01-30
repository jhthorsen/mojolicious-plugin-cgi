package Mojolicious::Plugin::CGI;

=head1 NAME

Mojolicious::Plugin::CGI - Run CGI script from Mojolicious

=head1 VERSION

0.17

=head1 DESCRIPTION

This plugin enable L<Mojolicious> to run Perl CGI scripts. It does so by forking
a new process with a modified environment and reads the STDOUT in a non-blocking
manner.

=head1 SYNOPSIS

=head2 Standard usage

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

=head2 Support for semicolon in query string

  plugin CGI => { support_semicolon_in_query_string => 1 };

The code above need to be added before other plugins or handler which use
L<Mojo::Message::Request/url>. It will inject a C<before_dispatch>
hook which saves the original QUERY_STRING, before it is split on
"&" in L<Mojo::Parameters>.

This is an EXPERIMENTAL feature.

=cut

use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util 'b64_decode';
use File::Basename;
use File::Spec;
use Sys::Hostname;
use IO::Pipely 'pipely';
use POSIX 'WNOHANG';
use Socket qw( AF_INET inet_aton );
use constant CHUNK_SIZE           => 131072;
use constant CHECK_CHILD_INTERVAL => $ENV{CHECK_CHILD_INTERVAL} || 0.01;
use constant DEBUG                => $ENV{MOJO_PLUGIN_CGI_DEBUG} || 0;
use constant READ                 => 0;
use constant WRITE                => 1;

our $VERSION      = '0.17';
our %ORIGINAL_ENV = %ENV;

=head1 ATTRIBUTES

=head2 env

Holds a hash ref containing the environment variables that should be
used when starting the CGI script. Defaults to C<%ENV> when this module
was loaded.

=head2 ioloop

Holds a L<Mojo::IOLoop> object.

=cut

has env    => sub { +{%ORIGINAL_ENV} };
has ioloop => sub { Mojo::IOLoop->singleton };

=head1 METHODS

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
  my ($self, $c) = @_;
  my $tx             = $c->tx;
  my $req            = $tx->req;
  my $headers        = $req->headers;
  my $content_length = $req->content->is_multipart ? $req->body_size : $headers->content_length;
  my $remote_user    = '';

  if (my $userinfo = $c->req->url->to_abs->userinfo) {
    $remote_user = $userinfo =~ /([^:]+)/ ? $1 : '';
  }
  elsif (my $authenticate = $headers->authorization) {
    $remote_user = $authenticate =~ /Basic\s+(.*)/ ? b64_decode $1 : '';
    $remote_user = $remote_user =~ /([^:]+)/       ? $1            : '';
  }

  return (
    %{$self->env},
    CONTENT_LENGTH => $content_length        || 0,
    CONTENT_TYPE   => $headers->content_type || '',
    GATEWAY_INTERFACE => 'CGI/1.1',
    HTTP_COOKIE       => $headers->cookie || '',
    HTTP_HOST         => $headers->host || '',
    HTTP_REFERER      => $headers->referrer || '',
    HTTP_USER_AGENT   => $headers->user_agent || '',
    HTTPS             => $req->is_secure ? 'YES' : 'NO',

    #PATH => $req->url->path,
    PATH_INFO => '/' . ($c->stash('path_info') || ''),
    QUERY_STRING => $c->stash('cgi.query_string') || $req->url->query->to_string,
    REMOTE_ADDR => $tx->remote_address,
    REMOTE_HOST => gethostbyaddr(inet_aton($tx->remote_address || '127.0.0.1'), AF_INET) || '',
    REMOTE_PORT => $tx->remote_port,
    REMOTE_USER => $remote_user,
    REQUEST_METHOD  => $req->method,
    SCRIPT_FILENAME => $self->{script},
    SCRIPT_NAME     => $c->url_for($self->{route}->name, {path_info => ''})->path->to_string,
    SERVER_ADMIN => $ENV{USER} || '',
    SERVER_NAME  => hostname,
    SERVER_PORT  => $tx->local_port,
    SERVER_PROTOCOL => $req->is_secure ? 'HTTPS' : 'HTTP',    # TODO: Version is missing
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
  my ($self, $app, $args) = @_;
  my $pids = $app->defaults->{'mojolicious_plugin_cgi.pids'} ||= {};
  my ($before, $name);

  if (ref $args eq 'ARRAY') {
    $self->{route}  = shift @$args;
    $self->{script} = shift @$args;
  }
  elsif ($args->{support_semicolon_in_query_string}) {
    $app->hook(before_dispatch => sub { $_[0]->stash('cgi.query_string' => $_[0]->req->url->query->to_string); });
    return;
  }
  else {
    $self->{$_} ||= $args->{$_} for keys %$args;
  }

  $before = $self->{before} || sub { };
  $app->defaults->{'mojolicious_plugin_cgi.tid'}
    ||= $self->ioloop->recurring(CHECK_CHILD_INTERVAL, sub { _waitpids($pids); });

  $name = basename $self->{script};
  $self->{script} = File::Spec->rel2abs($self->{script}) || $self->{script};
  $self->{route} = $app->routes->any("$self->{route}/*path_info", {path_info => ''}) unless ref $self->{route};
  $self->{route}->to(
    cb => sub {
      my $c      = shift;
      my $log    = $c->app->log;
      my @stderr = $self->{errlog} ? () : pipely;
      my @stdout = pipely;
      my $stdin  = $self->_stdin($c);
      my $pid;

      $c->$before;
      defined($pid = fork) or die "Failed to fork: $!";

      unless ($pid) {
        Mojo::IOLoop->reset;
        my @STDERR = @stderr ? ('>&', fileno $stderr[WRITE]) : ('>>', $self->{errlog});
        warn "[CGI:$name:$$] <<< (@{[$stdin->slurp]})\n" if DEBUG;
        %ENV = $self->emulate_environment($c);
        open STDIN, '<', $stdin->path or die "STDIN @{[$stdin->path]}: $!" if -s $stdin->path;
        open STDERR, $STDERR[0], $STDERR[1] or die "STDERR: @stderr: $!";
        open STDOUT, '>&', fileno $stdout[WRITE] or die "STDOUT: $!";
        select STDERR;
        $| = 1;
        select STDOUT;
        $| = 1;
        { exec $self->{script} }
        die "Could not execute $self->{script}: $!";
      }

      $log->debug("[CGI:$name:$pid] START $self->{script}");
      $pids->{$pid} = $name;

      for my $p (\@stdout, \@stderr) {
        next unless $p->[READ];
        close $p->[WRITE];
        $p->[READ] = Mojo::IOLoop::Stream->new($p->[READ])->timeout(0);
        $self->ioloop->stream($p->[READ]);
      }

      $c->delay(
        sub {
          my ($delay) = @_;
          $c->stash('cgi.pid' => $pid, 'cgi.stdin' => $stdin);
          $stderr[READ]->on(read => $self->_stderr_cb($log, "CGI:$name:$pid")) if $stderr[READ];
          $stdout[READ]->on(read => $self->_stdout_cb($c, "CGI:$name:$pid"));
          $stdout[READ]->on(close => $delay->begin);
        },
        sub {
          my ($delay) = @_;
          warn "[CGI:$name:$pid] Child closed STDOUT\n" if DEBUG;
          unlink $stdin->path or die "Could not remove STDIN @{[$stdin->path]}" if -e $stdin->path;
          _waitpids($pids);
          $c->finish;
        },
      );
    }
  );
}

sub _stderr_cb {
  my ($self, $log, $log_key) = @_;
  my $buf = '';

  return sub {
    my ($stream, $chunk) = @_;
    warn "[$log_key] !!! ($chunk)\n" if DEBUG;
    $buf .= $chunk;
    $log->warn("[$log_key] $1") while $buf =~ s!^(.+)[\r\n]+$!!m;
  };
}

sub _stdout_cb {
  my ($self, $c, $log_key) = @_;
  my $buf = '';
  my $headers;

  return sub {
    my ($stream, $chunk) = @_;
    warn "[$log_key] >>> ($chunk)\n" if DEBUG;

    if ($headers) {    # true if HTTP header has been written to client
      return $c->write($chunk);
    }

    $buf .= $chunk;
    $buf =~ s/^(.*?\x0a\x0d?\x0a\x0d?)//s or return;    # false until all headers has been read from the CGI script
    $headers = $1;

    if ($headers =~ /^HTTP/) {
      $c->res->parse($headers);
    }
    else {
      $c->res->code($headers =~ /Location:/ ? 302 : 200);
      $c->res->parse($c->res->get_start_line_chunk(0) . $headers);
    }

    $c->write($buf) if length $buf;
  };
}

sub _stdin {
  my ($self, $c) = @_;
  my $stdin;

  if ($c->req->content->is_multipart) {
    $stdin = Mojo::Asset::File->new;
    $stdin->add_chunk($c->req->build_body);
  }
  else {
    $stdin = $c->req->content->asset;
  }

  return $stdin if $stdin->isa('Mojo::Asset::File');
  return Mojo::Asset::File->new->add_chunk($stdin->slurp);
}

sub _waitpids {
  my $pids = shift;

  for my $pid (keys %$pids) {
    local $SIG{CHLD} = 'DEFAULT';    # no idea why i need to do this, but it seems like waitpid() below return -1 if not
    local ($?, $!);
    next unless $pid == waitpid $pid, WNOHANG;
    my $name = delete $pids->{$pid} || 'unknown';
    my ($exit_value, $signal) = ($? >> 8, $? & 127);
    warn "[CGI:$name:$pid] Child exit_value=$exit_value ($signal)\n" if DEBUG;
  }
}

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, Jan Henning Thorsen

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

1;
