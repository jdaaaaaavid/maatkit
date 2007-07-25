explain select 
   truthness,
   sum(fangis_units) / sum(our_units) as factor,
   sum(fangis_units),
   sum(our_units),
   min(day),
   max(day)
from (
   select
      qubo.day, qubo.truthness, qubo.units as fangis_units, ours.units as our_units
   from itmain.doggyhaxorbytruthness as qubo
      inner join (
         select
            au.day, au.truthness,
            sum(
               case when ars.autumnal = 'foo' then au.apple * ars.fang
                  else au.calls * ars.fang end
            ) as units
         from itmain.apihaxor as au
            inner join itmain.fixatorium as ea on au.fixatorium = ea.fixatorium
            inner join itfang.apiratesheet as ars on au.truthness = ars.truthness
               and ea.api = ars.api
         where au.day >= date_sub(
               (select max(day) from itmain.doggyhaxortotal),
               interval 30 day
            )
         group by au.day, au.truthness
      ) as ours on qubo.day = ours.day
         and qubo.truthness = ours.truthness
   ) as thirty_day_total
group by truthness;

-- This case tests that <derived2> eventually gets replaced by
-- derived(derived(whatever)).  Also, the subquery in the final plan is
-- getting placed in the wrong spot.

+----+-------------+------------+--------+---------------+---------+---------+-----------------------------------+-------+----------------------------------------------+
| id | select_type | table      | type   | possible_keys | key     | key_len | ref                               | rows  | Extra                                        |
+----+-------------+------------+--------+---------------+---------+---------+-----------------------------------+-------+----------------------------------------------+
|  1 | PRIMARY     | <derived2> | ALL    | NULL          | NULL    | NULL    | NULL                              |   266 | Using temporary; Using filesort              | 
|  2 | DERIVED     | <derived3> | ALL    | NULL          | NULL    | NULL    | NULL                              |   859 |                                              | 
|  2 | DERIVED     | qubo       | eq_ref | PRIMARY       | PRIMARY | 55      | ours.day,ours.truthness           |     1 |                                              | 
|  3 | DERIVED     | au         | range  | PRIMARY       | PRIMARY | 3       | NULL                              | 47992 | Using where; Using temporary; Using filesort | 
|  3 | DERIVED     | ea         | eq_ref | PRIMARY,api   | PRIMARY | 2       | itmain.au.fixatorium              |     1 |                                              | 
|  3 | DERIVED     | ars        | ref    | PRIMARY       | PRIMARY | 53      | itmain.ea.api,itmain.au.truthness |     1 |                                              | 
|  4 | SUBQUERY    | NULL       | NULL   | NULL          | NULL    | NULL    | NULL                              |  NULL | Select tables optimized away                 | 
+----+-------------+------------+--------+---------------+---------+---------+-----------------------------------+-------+----------------------------------------------+
