#!/usr/bin/perl

# This program is copyright (c) 2007 Baron Schwartz.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.
use strict;
use warnings FATAL => 'all';

use Test::More tests => 27;
use English qw(-no_match_vars);

require "../QueryRewriter.pm";

my $q = new QueryRewriter();

is(
   $q->norm("select \n--bar\n foo"),
   'select foo',
   'Removes one-line comments',
);

is(
   $q->norm('SELECT * from foo where a = 5'),
   'select * from foo where a = N',
   'Lowercases, replaces integer',
);

is(
   $q->norm('select 0e0, +6e-30, -6.00 from foo where a = 5.5 or b=0.5 or c=.5'),
   'select N, N, N from foo where a = N or b=N or c=N',
   'Floats',
);

is(
   $q->norm("select 0x0, x'123', 0b1010, b'10101' from foo"),
   'select N, N, N, N from foo',
   'Hex/bit',
);

is(
   $q->norm(" select  * from\nfoo where a = 5"),
   'select * from foo where a = N',
   'Collapses whitespace',
);

is(
   $q->norm("select * from foo where a in (5) and b in (5, 8,9 ,9 , 10)"),
   'select * from foo where a in (N) and b in(N+)',
   'IN lists',
);

is(
   $q->norm("select foo_1 from foo_2_3"),
   'select foo_N from foo_N_N',
   'Numeric table names',
);

is(
   $q->norm("insert into abtemp.coxed select foo.bar from foo"),
   'insert into abtemp.coxed select foo.bar from foo',
   'A string that needs no changes',
);

is(
   $q->norm('insert into foo(a, b, c) values(2, 4, 5)'),
   'insert into foo(a, b, c) values(N+)',
   'VALUES lists',
);

is($q->convert(), undef, 'No query');

is(
   $q->convert(
      'replace into foo select * from bar',
   ),
   'select * from bar',
   'replace select',
);

is(
   $q->convert(
      'replace into foo select`faz` from bar',
   ),
   'select`faz` from bar',
   'replace select',
);

is(
   $q->convert(
      'insert into foo(a, b, c) values(1, 3, 5)',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'insert',
);

is(
   $q->convert(
      'replace into foo(a, b, c) values(1, 3, 5) on duplicate key update foo=bar',
   ),
   'select * from  foo where a=1 and  b= 3 and  c= 5',
   'replace with ODKU',
);

is(
   $q->convert(
      'replace into foo(a, b, c) values(now(), "3", 5)',
   ),
   'select * from  foo where a=now() and  b= "3" and  c= 5',
   'replace with complicated expressions',
);

is(
   $q->convert(
      'replace into foo(a, b, c) values(current_date - interval 1 day, "3", 5)',
   ),
   'select * from  foo where a=current_date - interval 1 day and  b= "3" and  c= 5',
   'replace with complicated expressions',
);

is(
   $q->convert(
      'insert into foo select * from bar join baz using (bat)',
   ),
   'select * from bar join baz using (bat)',
   'insert select',
);

is(
   $q->convert(
      'insert into foo select * from bar where baz=bat on duplicate key update',
   ),
   'select * from bar where baz=bat',
   'insert select on duplicate key update',
);

is(
   $q->convert(
      'update foo set bar=baz where bat=fiz',
   ),
   'select  bar=baz from foo where  bat=fiz',
   'update set',
);

is(
   $q->convert(
      'update foo inner join bar using(baz) set big=little',
   ),
   'select  big=little from foo inner join bar using(baz) ',
   'delete inner join',
);

is(
   $q->convert(
      'update foo set bar=baz limit 50',
   ),
   'select  bar=baz  from foo  limit 50 ',
   'update with limit',
);

is(
   $q->convert(
q{UPDATE foo.bar
SET    whereproblem= '3364', apple = 'fish'
WHERE  gizmo='5091'}
   ),
   q{select     whereproblem= '3364', apple = 'fish' from foo.bar where   gizmo='5091'},
   'unknown issue',
);

is(
   $q->convert(
      'delete from foo where bar = baz',
   ),
   'select * from  foo where bar = baz',
   'delete',
);

# Insanity...
is(
   $q->convert('
update db2.tbl1 as p
   inner join (
      select p2.col1, p2.col2
      from db2.tbl1 as p2
         inner join db2.tbl3 as ba
            on p2.col1 = ba.tbl3
      where col4 = 0
      order by priority desc, col1, col2
      limit 10
   ) as chosen on chosen.col1 = p.col1
      and chosen.col2 = p.col2
   set p.col4 = 149945'),
   'select  p.col4 = 149945 from db2.tbl1 as p
   inner join (
      select p2.col1, p2.col2
      from db2.tbl1 as p2
         inner join db2.tbl3 as ba
            on p2.col1 = ba.tbl3
      where col4 = 0
      order by priority desc, col1, col2
      limit 10
   ) as chosen on chosen.col1 = p.col1
      and chosen.col2 = p.col2 ',
   'SELECT in the FROM clause',
);

is($q->wrap(), undef, 'Cannot wrap undef');

is(
   $q->wrap(
      'select * from foo',
   ),
   'select 1 from (select * from foo) as x limit 1',
   'wrap in derived table',
);

is(
   $q->wrap('set timestamp=134'),
   'set timestamp=134',
   'Do not wrap non-SELECT queries',
);
