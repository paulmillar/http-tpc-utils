#!/bin/bash
#
#  Run smoke-test.sh on all endpoints

cleanup() {
    rm -f $FILES_TO_DELETE
}

trap cleanup EXIT

BASE=$(cd $(dirname $0)/..;pwd)
SMOKE_OUTPUT=$(mktemp)
RESULTS=$(mktemp)
FAILURES=$(mktemp)
FILES_TO_DELETE="$SMOKE_OUTPUT $RESULTS $FAILURES"


SOUND_ENDPOINT_RE="0 failed, 0 skipped"

cat $BASE/etc/endpoints | while read name type url; do
    bin/smoke-test.sh -f $url > $SMOKE_OUTPUT
    if [ $? -ne 0 ]; then
	[ -s $FAILURES ] && echo -e "\n" >> $FAILURES
	echo $name >> $FAILURES
	head -n-2 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g' | awk '{print "    "$0}' >> $FAILURES
    fi
    echo -e "$name\t$type\t$(tail -1 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g')" >> $RESULTS
done

column -t $RESULTS -s $'\t' > $SMOKE_OUTPUT

if grep -q "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT; then
    echo
    echo "SOUND ENDPOINTS"
    echo
    grep "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT
fi

if grep -v -q "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT; then
    echo
    echo "PROBLEMATIC ENDPOINTS"
    echo
    grep -v "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT
fi

if grep -q "\[\*\]" $SMOKE_OUTPUT; then
    echo
    echo "  [*]  Indicates one or more known issues with the software."
    echo
    cat $FAILURES
fi

