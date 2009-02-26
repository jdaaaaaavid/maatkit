# This program is copyright 2007-@CURRENTYEAR@ Baron Schwartz.
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
# ###########################################################################
# TableParser package $Revision$
# ###########################################################################
package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG};

sub new {
   my ( $class ) = @_;
   return bless {}, $class;
}

# Several subs in this module require either a $ddl or $tbl param.
#
# $ddl is the return value from MySQLDump::get_create_table() (which returns
# the output of SHOW CREATE TALBE).
#
# $tbl is the return value from the sub below, parse().
#
# And some subs have an optional $opts param which is a hashref of options.
# $opts->{mysql_version} is typically used, which is the return value from
# VersionParser::parser() (which returns a zero-padded MySQL version,
# e.g. 004001000 for 4.1.0).

sub parse {
   my ( $self, $ddl, $opts ) = @_;

   if ( ref $ddl eq 'ARRAY' ) {
      if ( lc $ddl->[0] eq 'table' ) {
         $ddl = $ddl->[1];
      }
      else {
         return {
            engine => 'VIEW',
         };
      }
   }

   if ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "Cannot parse table definition; is ANSI quoting "
         . "enabled or SQL_QUOTE_SHOW_CREATE disabled?";
   }

   # Lowercase identifiers to avoid issues with case-sensitivity in Perl.
   # (Bug #1910276).
   $ddl =~ s/(`[^`]+`)/\L$1/g;

   my $engine = $self->get_engine($ddl);

   my @defs   = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols   = map { $_ =~ m/`([^`]+)`/g } @defs;
   MKDEBUG && _d('Columns: ' . join(', ', @cols));

   # Save the column definitions *exactly*
   my %def_for;
   @def_for{@cols} = @defs;

   # Find column types, whether numeric, whether nullable, whether
   # auto-increment.
   my (@nums, @null);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};
      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   # TODO: passing is_nullable this way is just a quick hack. Ultimately,
   # we probably should decompose this sub further, taking out the block
   # above that parses col props like nullability, auto_inc, type, etc.
   my %keys = $self->get_keys($ddl, $opts, \%is_nullable);

   return {
      cols           => \@cols,
      col_posn       => { map { $cols[$_] => $_ } 0..$#cols },
      is_col         => { map { $_ => 1 } @cols },
      null_cols      => \@null,
      is_nullable    => \%is_nullable,
      is_autoinc     => \%is_autoinc,
      keys           => \%keys,
      defs           => \%def_for,
      numeric_cols   => \@nums,
      is_numeric     => \%is_numeric,
      engine         => $engine,
      type_for       => \%type_for,
   };
}

# Sorts indexes in this order: PRIMARY, unique, non-nullable, any (shortest
# first, alphabetical).  Only BTREE indexes are considered.
# TODO: consider length as # of bytes instead of # of columns.
sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{is_unique} <=> !$tbl->{keys}->{$b}->{is_unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   MKDEBUG && _d('Indexes sorted best-first: ' . join(', ', @indexes));
   return @indexes;
}

# Finds the 'best' index; if the user specifies one, dies if it's not in the
# table.
sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         # The user specified an index, so we can't choose our own.
         die "Index '$index' does not exist in table";
      }
      else {
         # Try to pick the best index.
         # TODO: eliminate indexes that have column prefixes.
         ($best) = $self->sort_indexes($tbl);
      }
   }
   MKDEBUG && _d("Best index found is " . ($best || 'undef'));
   return $best;
}

# Takes a dbh, database, table, quoter, and WHERE clause, and reports the
# indexes MySQL thinks are best for EXPLAIN SELECT * FROM that table.  If no
# WHERE, just returns an empty list.  If no possible_keys, returns empty list,
# even if 'key' is not null.  Only adds 'key' to the list if it's included in
# possible_keys.
sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   # Normalize columns to lowercase
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      MKDEBUG && _d("possible_keys=$expl->{possible_keys}");
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         MKDEBUG && _d("MySQL chose $expl->{key}");
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         MKDEBUG && _d('Before deduping: ' . join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      MKDEBUG && _d('Final list: ' . join(', ', @candidates));
      return @candidates;
   }
   else {
      MKDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub table_exists {
   my ( $self, $dbh, $db, $tbl, $q, $can_insert ) = @_;
   my $db_tbl = $q->quote($db, $tbl);
   my $sql    = $can_insert ? "REPLACE INTO $db_tbl " : '';
   $sql      .= "SELECT * FROM $db_tbl LIMIT 0";
   MKDEBUG && _d("table_exists check for $db_tbl: $sql");
   eval { $dbh->do($sql); };
   MKDEBUG && _d("eval error (if any): $EVAL_ERROR");
   return 0 if $EVAL_ERROR;
   return 1;
}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   MKDEBUG && _d('Storage engine: ', $engine || 'unknown');
   return $engine || undef;
}


# $ddl is a SHOW CREATE TABLE returned from MySQLDumper::get_create_table().
# The general format of a key is
# [FOREIGN|UNIQUE|PRIMARY|FULLTEXT|SPATIAL] KEY `name` [USING BTREE|HASH] (`cols`).
# Returns a hash of keys and their properties:
#    key => {
#       type         => BTREE, FULLTEXT or  SPATIAL
#       name         => column name, like: "foo_key"
#       colnames     => original col def string, like: "(`a`,`b`)"
#       cols         => arrayref containing the col names, like: [qw(a b)]
#       col_prefixes => arrayref containing any col prefixes (parallels cols)
#       is_unique    => 1 if the col is UNIQUE or PRIMARY
#       is_nullable  => true (> 0) if one or more col can be NULL
#       is_col       => hashref with key for each col=>1
#   },
#   key => ...
sub get_keys {
   my ( $self, $ddl, $opts, $is_nullable ) = @_;
   my %keys;

   KEY:
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      next KEY if $opts->{nofks} && $key =~ m/FOREIGN/;

      MKDEBUG && _d("Parsed key: $key");

      # Make allowances for HASH bugs in SHOW CREATE TABLE.  A non-MEMORY table
      # will report its index as USING HASH even when this is not supported.
      # The true type should be BTREE.  See
      # http://bugs.mysql.com/bug.php?id=22632
      my $engine = $self->get_engine($ddl);
      if ( $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      # Determine index type
      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      if ( $opts->{mysql_version} && $opts->{mysql_version} lt '004001000'
         && $engine =~ m/HEAP|MEMORY/i )
      {
         $type = 'HASH'; # MySQL pre-4.1 supports only HASH indexes on HEAP
      }

      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( split(',', $cols) ) {
         # Parse columns of index including potential column prefixes
         # E.g.: `a`,`b`(20)
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;

      MKDEBUG && _d("Key $name cols: " . join(', ', @cols));

      $keys{$name} = {
         name         => $name,
         type         => $type,
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         is_unique    => $unique,
         is_nullable  => scalar(grep { $is_nullable->{$_} } @cols),
         is_col       => { map { $_ => 1 } @cols },
      };
   }

   return %keys;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   # Use $$ instead of $PID in case the package
   # does not use English.
   print "# $package:$line $$ ", @_, "\n";
}

1;

# ###########################################################################
# End TableParser package
# ###########################################################################
