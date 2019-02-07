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
REPORT=$(mktemp)
FILES_TO_DELETE="$SMOKE_OUTPUT $RESULTS $FAILURES $REPORT"

SOUND_ENDPOINT_RE="0 failed, 0 skipped"

OUTPUT_DESCRIPTION="stdout"
while getopts "h?s:" opt; do
    case "$opt" in
        h|\?)
            echo "$0 [-s <addr>]"
            echo
            echo "-s  send report as an email to <addr>"
            exit 0
            ;;
        s)
            sendEmail="$OPTARG"
	    OUTPUT_DESCRIPTION="emailing"
            ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

fatal() {
    echo "$@"
    exit 1
}

runTests() {
    cat $BASE/etc/endpoints | while read name type url; do
	bin/smoke-test.sh -f $url > $SMOKE_OUTPUT
	if [ $? -ne 0 ]; then
	    [ -s $FAILURES ] && echo -e "\n" >> $FAILURES
	    echo $name >> $FAILURES
	    head -n-2 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g' | awk '{print "    "$0}' >> $FAILURES
	fi
	echo -e "$name\t$type\t$(tail -1 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g')" >> $RESULTS
    done
}

buildReport() {
    column -t $RESULTS -s $'\t' > $SMOKE_OUTPUT

    echo "DOMA-TPC smoke test $(date --iso-8601=m)"

    if grep -q "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT; then
	echo
	echo "SOUND ENDPOINTS"
	echo
	grep "$SOUND_ENDPOINT_RE" $SMOKE_OUTPUT | sed 's/:.*/ successfully./'
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
    fi
} > $REPORT


voms-proxy-info -e >/dev/null 2>&1 || fatal "Need valid X.509 proxy"
voms-proxy-info -e -hours 1 >/dev/null 2>&1 || fatal "X.509 proxy expires too soon"
voms-proxy-info --acexists dteam 2>/dev/null || fatal "X.509 proxy does not assert dteam membership"

echo "Building report for ${OUTPUT_DESCRIPTION}..."
runTests
buildReport

if [ -n "$sendEmail" ]; then
    echo "Sending email to $sendEmail"
    date=$(date --iso-8601=m)

    ## Rename the file as the filename is used as the attachment's name
    FAILURES2=/tmp/smoke-test-details-$date.txt
    cp $FAILURES $FAILURES2
    FILES_TO_DELETE="$FILES_TO_DELETE $FAILURES2"

    mail -s "Smoke test report $date" $sendEmail -A $FAILURES2 < $REPORT
else
    cat $REPORT
    echo
    cat $FAILURES
fi
