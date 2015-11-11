#!/usr/bin/env perl
use strict;
use warnings;

print "Status: 304 Not Modified\r\n";
print "X-Test: if-none-match seen: $ENV{HTTP_IF_NONE_MATCH}\r\n";
print "\r\n";
