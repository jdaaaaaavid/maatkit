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
require "$trunk/mk-table-sync/mk-table-sync";

my $output;
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
   plan tests => 1;
}

$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
$sb->create_dbs($master_dbh, [qw(test)]);

# #############################################################################
# Issue 627: Results for mk-table-sync --replicate may be incorrect
# #############################################################################
diag(`/tmp/12345/use < $trunk/mk-table-sync/t/samples/issue_375.sql`);
sleep 1;

# Make the table differ.
# (10, '2009-09-03 14:18:00', 'k'),    -> (10, '2009-09-03 14:18:00', 'z'),
# (100, '2009-09-06 15:01:23', 'cv');  -> (100, '2009-09-06 15:01:23', 'zz');
$slave_dbh->do('UPDATE issue_375.t SET foo="z" WHERE id=10');
$slave_dbh->do('UPDATE issue_375.t SET foo="zz" WHERE id=100');

# Checksum and replicate.
diag(`$trunk/mk-table-checksum/mk-table-checksum --create-replicate-table --replicate issue_375.checksum h=127.1,P=12345,u=msandbox,p=msandbox -d issue_375 -t t > /dev/null`);
diag(`$trunk/mk-table-checksum/mk-table-checksum --replicate issue_375.checksum h=127.1,P=12345,u=msandbox,p=msandbox  --replicate-check 1 > /dev/null`);

# And now sync using the replicated checksum results/differences.
$output = output(
   sub { mk_table_sync::main('--sync-to-master', 'h=127.1,P=12346,u=msandbox,p=msandbox', qw(--replicate issue_375.checksum --print)) },
   trf => \&remove_traces,
);
is(
   $output,
   "REPLACE INTO `issue_375`.`t`(`id`, `updated_at`, `foo`) VALUES ('10', '2009-09-03 14:18:00', 'k');
REPLACE INTO `issue_375`.`t`(`id`, `updated_at`, `foo`) VALUES ('100', '2009-09-06 15:01:23', 'cv');
",
   'Simple --replicate'
);

# Note how the columns are out of order (tbl order is: id, updated_at, foo).
# This is issue http://code.google.com/p/maatkit/issues/detail?id=371

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
$sb->wipe_clean($slave_dbh);
exit;
