#!perl

use 5.010;
use strict;
use warnings;

# what we have here are casual tests. more complete tests in Sah's spectest

use Data::Sah::Normalize qw(normalize_clset normalize_schema);
use Test::More 0.98;

is_deeply(normalize_clset({'!a'=>1, 'b|'=>[2,3], 'c&'=>[4,5], 'd='=>6}),
          {a=>1, 'a.op'=>'not',
           b=>[2,3], 'b.op'=>'or',
           c=>[4,5], 'c.op'=>'and',
           d=>6, 'd.is_expr'=>1,
       });

is_deeply(normalize_schema('int'), [int => {}, {}]);
is_deeply(normalize_schema('int*'), [int => {req=>1}, {}]);

DONE_TESTING:
done_testing;
