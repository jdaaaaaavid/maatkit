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
require "$trunk/mk-slave-restart/mk-slave-restart";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave_dbh  = $sb->get_dbh_for('slave1');

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave';
}
else {
   plan tests => 14;
}

$sb->create_dbs($master_dbh, ['test']);
$master_dbh->do('CREATE TABLE test.t (a INT)');
my $i = 0;
MaatkitTest::wait_until(
   sub {
      my $r;
      eval {
         $r = $slave_dbh->selectrow_arrayref('SHOW TABLES FROM test LIKE "t"');
      };
      return 1 if ($r->[0] || '') eq 't';
      diag('Waiting for CREATE TABLE to replicate...') unless $i++;
      return 0;
   },
   0.5,
   30,
);

# Bust replication
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
my $output = `/tmp/12346/use -e 'show slave status'`;
like($output, qr/Table 'test.t' doesn't exist'/, 'It is busted');

# Start an instance
diag(`$trunk/mk-slave-restart/mk-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --daemonize --pid /tmp/mk-slave-restart.pid --log /tmp/mk-slave-restart.log`);
$output = `ps -eaf | grep 'mk-slave-restart \-\-max\-sleep ' | grep -v grep | grep -v mk-slave-restart.t`;
like($output, qr/mk-slave-restart --max/, 'It lives');

unlike($output, qr/Table 'test.t' doesn't exist'/, 'It is not busted');

ok(-f '/tmp/mk-slave-restart.pid', 'PID file created');
ok(-f '/tmp/mk-slave-restart.log', 'Log file created');

my ($pid) = $output =~ /\s+(\d+)\s+/;
$output = `cat /tmp/mk-slave-restart.pid`;
is($output, $pid, 'PID file has correct PID');

diag(`$trunk/mk-slave-restart/mk-slave-restart --stop -q`);
sleep 1;
$output = `ps -eaf | grep mk-slave-restart | grep -v grep`;
unlike($output, qr/mk-slave-restart --max/, 'It is dead');

diag(`rm -f /tmp/mk-slave-re*`);
ok(! -f '/tmp/mk-slave-restart.pid', 'PID file removed');

# #############################################################################
# Issue 118: mk-slave-restart --error-numbers option is broken
# #############################################################################
$output = `$trunk/mk-slave-restart/mk-slave-restart --stop --sentinel /tmp/mk-slave-restartup --error-numbers=1205,1317`;
like($output, qr{Successfully created file /tmp/mk-slave-restartup}, '--error-numbers works (issue 118)');

diag(`rm -f /tmp/mk-slave-re*`);

# #############################################################################
# Issue 459: mk-slave-restart --error-text is broken
# #############################################################################
# Bust replication again.  At this point, the master has test.t but
# the slave does not.
$master_dbh->do('DROP TABLE IF EXISTS test.t');
$master_dbh->do('CREATE TABLE test.t (a INT)');
sleep 1;
$slave_dbh->do('DROP TABLE test.t');
$master_dbh->do('INSERT INTO test.t SELECT 1');
$output = `/tmp/12346/use -e 'show slave status'`;
like(
   $output,
   qr/Table 'test.t' doesn't exist'/,
   'It is busted again'
);

# Start an instance
$output = `$trunk/mk-slave-restart/mk-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --error-text "doesn't exist" --run-time 1s 2>&1`;
unlike(
   $output,
   qr/Error does not match/,
   '--error-text works (issue 459)'
);

# ###########################################################################
# Issue 391: Add --pid option to all scripts
# ###########################################################################
`touch /tmp/mk-script.pid`;
$output = `$trunk/mk-slave-restart/mk-slave-restart --max-sleep .25 -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --pid /tmp/mk-script.pid 2>&1`;
like(
   $output,
   qr{PID file /tmp/mk-script.pid already exists},
   'Dies if PID file already exists (--pid without --daemonize) (issue 391)'
);
`rm -rf /tmp/mk-script.pid`;

# #############################################################################
# Issue 662: Option maxlength does not exist
# #############################################################################
my $ret = system("$trunk/mk-slave-restart/mk-slave-restart -h 127.0.0.1 -P 12346 -u msandbox -p msandbox --monitor --stop --max-sleep 1 --run-time 1 >/dev/null 2>&1");
is(
   $ret >> 8,
   0,
   "--monitor --stop doesn't cause error"
);

# #############################################################################
#  Issue 673: Use of uninitialized value in numeric gt (>)
# #############################################################################
$output = `$trunk/mk-slave-restart/mk-slave-restart --monitor  --error-numbers 1205,1317 --quiet -F /tmp/12346/my.sandbox.cnf  --run-time 1 2>&1`;
is(
   $output,
   '',
   'No error with --quiet (issue 673)'
);

# #############################################################################
# Done.
# #############################################################################
diag(`rm -f /tmp/mk-slave-re*`);
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
