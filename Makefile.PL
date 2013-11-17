use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious::Plugin::CGI',
  ABSTRACT_FROM => 'lib/Mojolicious/Plugin/CGI.pm',
  VERSION_FROM => 'lib/Mojolicious/Plugin/CGI.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  LICENSE => 'perl',
  PREREQ_PM => {
    'Mojolicious' => '4.00',
  },
  BUILD_REQUIRES => {
    'Test::More' => 0.90,
  },
  META_MERGE => {
    resources => {
      license => 'http://dev.perl.org/licenses/',
      homepage => 'https://metacpan.org/module/Mojolicious::Plugin::CGI',
      bugtracker => 'https://github.com/jhthorsen/mojolicious-plugin-cgi/issues',
      repository => 'https://github.com/jhthorsen/mojolicious-plugin-cgi'
    },
  },
  test => {
    TESTS => 't/*.t',
  },
);
