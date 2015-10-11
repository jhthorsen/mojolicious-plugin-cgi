#!/usr/bin/env perl
use strict;
use warnings;

print "HTTP/1.1 403 Payment Required\r\n";
print "Content-Type: text/html; charset=ISO-8859-1\r\n";
print "\r\n";
print "<body><p>This is the paywall.\n";
