#!/usr/bin/env perl
print "Content-Type: text/plain\n\r";
print "\n\rENVIRON";
print "MENT\n";
print "$_=$ENV{$_}\n" for sort keys %ENV;
