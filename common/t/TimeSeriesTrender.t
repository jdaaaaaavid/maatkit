#!/usr/bin/perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More tests => 1;

use TimeSeriesTrender;
use MaatkitTest;

my $result;
my $tst = new TimeSeriesTrender(
   callback => sub { $result = $_[0]; },
);

$tst->set_time('5');
map { $tst->add_number($_) }
   qw(1 2 1 2 12 23 2 2 3 3 21 3 3 1 1 2 3 1 2 12 2
      3 1 3 2 22 2 2 2 2 3 1 1); 
$tst->set_time('6');

is_deeply($result,
   {
      ts    => 5,
      stdev => 6.09038140334414,
      avg   => 4.42424242424242,
      min   => 1,
      max   => 23,
      cnt   => 33,
      sum   => 146,
   },
   'Simple stats test');

# #############################################################################
# Done.
# #############################################################################
