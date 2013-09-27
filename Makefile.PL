use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious::Plugin::CGI',
  VERSION_FROM => 'lib/Mojolicious/Plugin/CGI.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  PREREQ_PM => {
    'Mojolicious' => '4.00',
  },
  META_MERGE => {
    resources => {
      repository => 'https://github.com/jhthorsen/mojolicious-plugin-cgi',
    },
  },
  test => {
    TESTS => 't/*.t',
  },
);
