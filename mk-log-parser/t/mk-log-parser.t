#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 20;
use English qw(-no_match_vars);

# #############################################################################
# First, some basic input-output diffs to make sure that
# the analysis reports are correct.
# #############################################################################

# Returns true (1) if there's no difference between the
# cmd's output and the expected output.
sub no_diff {
   my ( $cmd, $expected_output ) = @_;
   `$cmd > /tmp/mk-log-parser_test`;
   `cat /tmp/mk-log-parser_test > $expected_output`;
   my $retval = system("diff /tmp/mk-log-parser_test $expected_output");
   `rm -rf /tmp/mk-log-parser_test`;
   $retval = $retval >> 8;
   return !$retval;
}

my $run_with = '../mk-log-parser --noheader --top 10 ../../common/t/samples/';
my $run_notop = '../mk-log-parser --noheader ../../common/t/samples/';

ok(
   no_diff($run_with.'slow001.txt', 'samples/slow001_report.txt'),
   'Analysis for slow001'
);
ok(
   no_diff($run_with.'slow002.txt', 'samples/slow002_report.txt'),
   'Analysis for slow002'
);
ok(
   no_diff($run_notop.'slow002.txt --top 5%', 'samples/slow002_top_report.txt'),
   'Analysis for slow002 with --top',
);
ok(
   no_diff($run_with.'slow003.txt', 'samples/slow003_report.txt'),
   'Analysis for slow003'
);
ok(
   no_diff($run_with.'slow004.txt', 'samples/slow004_report.txt'),
   'Analysis for slow004'
);
ok(
   no_diff($run_with.'slow006.txt', 'samples/slow006_report.txt'),
   'Analysis for slow006'
);
ok(
   no_diff($run_with.'slow008.txt', 'samples/slow008_report.txt'),
   'Analysis for slow008'
);
ok(
   no_diff($run_with.'slow011.txt', 'samples/slow011_report.txt'),
   'Analysis for slow011'
);
ok(
   no_diff($run_with.'slow013.txt', 'samples/slow013_report.txt'),
   'Analysis for slow013'
);
ok(
   no_diff($run_with.'slow014.txt', 'samples/slow014_report.txt'),
   'Analysis for slow014'
);

# #############################################################################
# Test cmd line op sanity.
# #############################################################################
my $output = `../mk-log-parser --review h=127.1,P=12345`;
like($output, qr/--review DSN requires a D/, 'Dies if no D part in --review DSN');
$output = `../mk-log-parser --review h=127.1,P=12345,D=test`;
like($output, qr/--review DSN requires a D/, 'Dies if no t part in --review DSN');

$output = `../mk-log-parser --analyze`;
like($output, qr/--analyze requires --review/, '--analyze requires --review');

# #############################################################################
# Tests for query reviewing.
# #############################################################################
require '../../common/DSNParser.pm';
require '../../common/Sandbox.pm';
use Data::Dumper;
$Data::Dumper::Indent=1;
my $dp  = new DSNParser();
my $sb  = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $dbh = $sb->get_dbh_for('master');
SKIP: {
   skip 'Cannot connect to sandbox master', 7 if !$dbh;

   $sb->create_dbs($dbh, ['test']);
   $sb->load_file('master', 'samples/query_review.sql');

   $output = 'foo'; # clear previous test results
   $output = `${run_with}slow006.txt --review h=127.1,P=12345,D=test,t=query_review`;
   my $res = $dbh->selectall_arrayref('SELECT * FROM test.query_review');
   is_deeply(
      $res,
      [
         [
         '11676753765851784517',
         'select col from foo_tbl',
         'SELECT col FROM foo_tbl',
         '2007-12-18 11:48:27',
         '2007-12-18 11:49:30',
         undef,
         undef,
         undef,
         '3'
         ],
         [
         '15334040482108055940',
         'select col from bar_tbl',
         'SELECT col FROM bar_tbl',
         '2007-12-18 11:48:57',
         '2007-12-18 11:49:07',
         undef,
         undef,
         undef,
         '3'
         ],
      ],
      'Adds/updates queries to query review table'
   );
   is($output, '', '--review alone produces no output');

   # This time we'll run with --analze and since none of the queries
   # have been reviewed, the report should include both of them with
   # their respective query review info added to the report.
   ok(
      no_diff($run_with.'slow006.txt -AR h=127.1,P=12345,D=test,t=query_review', 'samples/slow006_AR_1.txt'),
      'Analyze-review pass 1 reports not-reviewed queries'
   );

   $res = $dbh->selectall_arrayref('SELECT * FROM test.query_review');
   ok( ($res->[0]->[8] == 6 && $res->[1]->[8] == 6), 'Analyze-review pass 1 updated cnt');

   # Mark a query as reviewed and run --analyze again and that query should
   # not be reported.
   $dbh->do('UPDATE test.query_review
      SET reviewed_by="daniel", reviewed_on="2008-12-24 12:00:00", comments="foo_tbl is ok, so are cranberries"
      WHERE checksum=11676753765851784517');
   ok(
      no_diff($run_with.'slow006.txt -AR h=127.1,P=12345,D=test,t=query_review', 'samples/slow006_AR_2.txt'),
      'Analyze-review pass 2 does not report the reviewed query'
   );

   # And a 4th pass with --reportall which should cause the reviewed query
   # to re-appear in the report with the reviewed_by, reviewed_on and comments
   # info included.
   ok(
      no_diff($run_with.'slow006.txt -AR h=127.1,P=12345,D=test,t=query_review   --reportall', 'samples/slow006_AR_4.txt'),
      'Analyze-review pass 4 with --reportall reports reviewed query'
   );

   # Test that reported review info gets all meta-columns dynamically.
   $dbh->do('ALTER TABLE test.query_review ADD COLUMN foo INT');
   $dbh->do('UPDATE test.query_review
      SET foo=42 WHERE checksum=15334040482108055940');
   ok(
      no_diff($run_with.'slow006.txt -AR h=127.1,P=12345,D=test,t=query_review', 'samples/slow006_AR_5.txt'),
      'Analyze-review pass 5 reports new review info column'
   );

   $sb->wipe_clean($dbh);
};

exit;
