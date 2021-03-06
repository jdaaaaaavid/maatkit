#!/usr/bin/env perl

BEGIN {
   die "The MAATKIT_WORKING_COPY environment variable is not set.  See http://code.google.com/p/maatkit/wiki/Testing"
      unless $ENV{MAATKIT_WORKING_COPY} && -d $ENV{MAATKIT_WORKING_COPY};
   unshift @INC, "$ENV{MAATKIT_WORKING_COPY}/common";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use MaatkitTest;
use Sandbox;
require "$trunk/mk-duplicate-key-checker/mk-duplicate-key-checker";

my $dp  = new DSNParser(opts=>$dsn_opts);
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');

if ( !$dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
else {
   plan tests => 1;
}

my $cnf    = "/tmp/12345/my.sandbox.cnf";
my $sample = "mk-duplicate-key-checker/t/samples/";
my @args   = ('-F', $cnf, qw(-h 127.1));

$sb->wipe_clean($dbh);
$sb->create_dbs($dbh, ['test']);

# #############################################################################
# Issue 331: mk-duplicate-key-checker crashes getting size of foreign keys
# #############################################################################

$sb->load_file('master', 'mk-duplicate-key-checker/t/samples/issue_331.sql', 'test');
ok(
   no_diff(
      sub { mk_duplicate_key_checker::main(@args, qw(-d issue_331)) },
      'mk-duplicate-key-checker/t/samples/issue_331.txt',
   ),
   'Issue 331 crash on fks'
);

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($dbh);
exit;
