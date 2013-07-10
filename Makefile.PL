use ExtUtils::MakeMaker;
WriteMakefile(
  NAME => 'Mojolicious-Plugin-CGI',
  VERSION_FROM => 'lib/Mojolicious/Plugin/CGI.pm',
  AUTHOR => 'Jan Henning Thorsen <jhthorsen@cpan.org>',
  PREREQ_PM => {
    'Mojolicious' => '4.00',
    'CGI::Compile' => 0.01,
    'SelectSaver' => 0.01,
  },
  test => {
    TESTS => 't/*.t',
  },
);
