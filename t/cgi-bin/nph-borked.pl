#!/usr/bin/env perl
use strict;
use warnings;

# When SERVER_PROTOCOL is set to "HTTP", the CGI module will just print HTTP and
# no version!
print "HTTP 403 Payment Required\r\n";
print "Content-Type: text/html; charset=ISO-8859-1\r\n";
print "\r\n";
print "<body><p>This is the borked paywall.\n";
