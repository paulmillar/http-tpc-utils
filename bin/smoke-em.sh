#!/bin/bash
#
#  Run smoke-test.sh on all endpoints

BASE=$(cd $(dirname $0)/..;pwd)
OUTPUT=$(mktemp)

rm -f results
cat $BASE/etc/sites | while read site url; do
    bin/smoke-test.sh -f $url > $OUTPUT
    echo -e "$site\t$(tail -1 $OUTPUT)" >> results
done
rm -f $OUTPUT

column -t results -s $'\t'
