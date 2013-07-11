package Mojolicious::Plugin::CGI;

=head1 NAME

Mojolicious::Plugin::CGI - Run CGI script from Mojolicious

=head1 VERSION

0.01

=head1 DESCRIPTION

This plugin enable the L<Mojolicious> application to run Perl CGI scripts.

=head1 NOTICE

Running CGI scripts does not mix well with non-blocking requests, since the
script will be executed inside the request as a blocking code ref.

TODO: Make it non-blocking.

=head1 SYNOPSIS

  use Mojolicious::Lite;

  plugin CGI => [ '/script' => '/path/to/cgi/script.pl' ];
  plugin CGI => {
    route => '/mount/point',
    script => '/path/to/cgi/script.pl',
    env => {}, # default is \%ENV
  };

  app->start;

=cut

use Mojo::Base 'Mojolicious::Plugin';
use CGI::Compile;
use File::Basename;
use File::Spec;
use POSIX qw/ :sys_wait_h /;
use SelectSaver;
use Sys::Hostname;
use Socket;

our $VERSION = '0.01';
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
    PATH => $req->url->path,
    PATH_INFO => $req->url->path,
    QUERY_STRING => $req->url->query->to_string,
    REMOTE_ADDR => $tx->remote_address,
    REMOTE_HOST => gethostbyaddr(inet_aton($tx->remote_address), AF_INET) || '',
    REMOTE_PORT => $tx->remote_port,
    REMOTE_USER => $c->session('username') || '', # TODO: Should probably be configurable
    REQUEST_METHOD => $req->method,
    SCRIPT_FILENAME => $self->{script},
    SCRIPT_NAME => $req->url->path =~ s!^/?\Q$base_path\E/?!!r,
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
  my $cb;

  if(ref $args eq 'ARRAY') {
    $self->{route} = shift @$args;
    $self->{script} = shift @$args;
  }
  else {
    $self->{$_} ||= $args->{$_} for keys %$args;
  }

  $self->{script} = File::Spec->rel2abs($self->{script});
  -r $self->{script} or die "Cannot read $self->{script}";
  $self->{name} = basename $self->{script};
  $cb = CGI::Compile->compile($self->{script});

  $self->{route} = $app->routes->any($self->{route}) unless ref $self->{route};
  $self->{route}->to(cb => sub {
    my $c = shift;

    $log->debug("Running $self->{script} ...");

    {
      my $saver = SelectSaver->new('::STDOUT');
      local *STDERR; tie *STDERR, 'Mojolicious::Plugin::CGI::STDERR', $log, $self->{name} if $got_log_file;
      local *STDIN; tie *STDIN, 'Mojolicious::Plugin::CGI::STDIN', $c->req->body;
      local *STDOUT; tie *STDOUT, 'Mojolicious::Plugin::CGI::STDOUT', $c->res;
      local %ENV = $self->emulate_environment($c);
      $cb->();
    }

    if(my $e = $c->res->error) {
      $c->render_exception("[$self->{name}] $e");
    }
    else {
      $c->finish;
    }
  });
}

=head1 AUTHOR

Jan Henning Thorsen - C<jhthorsen@cpan.org>

=cut

#=============================================================================
package # hide from CPAN
  Mojolicious::Plugin::CGI::STDERR;

sub TIEHANDLE { bless { log => $_[1], key => $_[2] }, $_[0] }
sub PRINT { $_[0]->{log}->error("[$_[0]->{key}] $_[1]") }
sub PRINTF { PRINT(shift, sprintf shift, @_) }

#=============================================================================
package # hide from CPAN
  Mojolicious::Plugin::CGI::STDIN;

sub TIEHANDLE { bless { body => $_[1], pos => 0 }, $_[0] }
sub READ {
  my($self, undef, $len, $offset) = @_;
  return 0 if $offset > length $self->{body};
  $offset ||= 0;
  $_[1] = substr $self->{body}, $offset, $len;
  $self->{pos} = $offset ? $offset + $len : $self->{pos} + $len;
  length $_[1];
}
sub READLINE {
  my $self = shift;
  my($pos, $buf);

  return if $self->{pos} == length $self->{body};
  pos($self->{body}) = $self->{pos};
  $self->{body} =~ /\n/;
  $pos = pos $self->{body} // length $self->{body};
  $buf = substr $self->{body}, $self->{pos}, $pos;
  $self->{pos} = $pos;
  $buf;
}

#=============================================================================
package # hide from CPAN
  Mojolicious::Plugin::CGI::STDOUT;

sub TIEHANDLE { bless { res => $_[1], buf => '' }, $_[0] }
sub PRINTF { PRINT(shift, sprintf shift, @_) }
sub PRINT {
  my $self = shift;
  my $res = $self->{res};

  if($self->{headers}) {
    $res->content->write($_[0]);
  }
  else {
    $self->{buf} .= $_[0];
    $self->{buf} =~ s/^(.*?\x0a\x0d?\x0a\x0d?)//s or return 1;
    $self->{headers} = $1;

    if($self->{headers} =~ /^HTTP/) {
      $res->parse($self->{headers});
    }
    else {
      $res->code(200);
      $res->parse($res->get_start_line_chunk(0) .$self->{headers});
    }

    $res->content->write($self->{buf});
  }

  return 1;
}

1;
