#!/usr/bin/perl
#PERL5LIB=lib ./example.cgi cgi
use Mojolicious::Lite;
plugin CGI => [ '/' => 't/cgi-bin/working.pl' ];
app->start;
