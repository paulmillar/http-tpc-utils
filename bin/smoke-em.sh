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
MAILER=mail
EXTENDED_TESTS=0
CLEAR_LINE="\e[2K"

SOUND_ENDPOINT_RE="successful (100%)"

OUTPUT_DESCRIPTION="stdout"
while getopts "h?s:m:x" opt; do
    case "$opt" in
        h|\?)
            echo "$0 -x [-s <addr> [-m <mailer>]]"
            echo
            echo "    -s  send report as an email to <addr>"
            echo "    -m  use <mailer> to send email: 'mail' and 'thunderbird'"
            echo "    -x  use extended tests, if supported"
            exit 0
            ;;
        s)
            sendEmail="$OPTARG"
            OUTPUT_DESCRIPTION="emailing"
            ;;
        m)
            MAILER="$OPTARG"
            ;;
        x)
            EXTENDED_TESTS=1
            ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

fatal() {
    echo "$@"
    exit 1
}

case $MAILER in
    mail|thunderbird)
        ;;
    *)
        fatal "Unknown mailer '$MAILER'"
        ;;
esac

runTests() {
    local options

    TOTAL=$(wc -l $BASE/etc/endpoints|awk '{print $1}')
    COUNT=1
    cat $BASE/etc/endpoints | while read name type workarounds url; do
        if [ $EXTENDED_TESTS -eq 1 ]; then
            case $type in
                dCache|DPM|StoRM)
                    options="-f -x"
                    ;;
                *)
                    options="-f"
                    ;;
            esac
        else
            options="-f"
        fi

	if [ "$workarounds" == "-" ]; then
	    unset hasWorkaround
	else
	    hasWorkaround="[*]"
	fi

	if [[ "$workarounds" == *L* ]]; then
	    options="$options -L"
	fi

        echo -n -e "${CLEAR_LINE}Testing: $name [$COUNT/$TOTAL] $options $url\r"
        COUNT=$(( $COUNT + 1 ))

        startTime=$(date +%s)
        bin/smoke-test.sh $options $url > $SMOKE_OUTPUT
        result=$?
        elapsedTime=$(( $(date +%s) - $startTime ))
        duration=$(printf "%02d:%02d" $(($elapsedTime/60)) $(($elapsedTime%60)))
        if [ $result -ne 0 ]; then
            [ -s $FAILURES ] && echo -e "\n" >> $FAILURES
            echo $name >> $FAILURES
            head -n-2 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g' | awk '{print "    "$0}' >> $FAILURES
        fi
        testCount=$(sed -n 's/^Of \([0-9]*\) tests.*/\1/p' $SMOKE_OUTPUT)
        testSuccess=$(sed -n 's/^Of [0-9]* tests.*: \([0-9]*\) successful.*/\1/p' $SMOKE_OUTPUT)
        testNonSuccessful=$(( $testCount - $testSuccess ))
        echo -e "$testNonSuccessful\t$name\t$type$hasWorkaround\t$(tail -1 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g')\t[in $duration]" >> $RESULTS
    done
    echo -n -e "${CLEAR_LINE}"
}

buildReport() {
    echo "DOMA-TPC smoke test $(date --iso-8601=m)"

    if grep -q "$SOUND_ENDPOINT_RE" $RESULTS; then
        echo
        echo "SOUND ENDPOINTS"
        echo
        grep "$SOUND_ENDPOINT_RE" $RESULTS \
            | cut -f2- \
            | sed 's/ *Of [0-9]* tests:.*\(\[in .*\]\)/\t\1/' \
            > $SMOKE_OUTPUT
        column -t $SMOKE_OUTPUT -s $'\t'
    fi

    if grep -v -q "$SOUND_ENDPOINT_RE" $RESULTS; then
        echo
        echo "PROBLEMATIC ENDPOINTS"
        echo
        grep -v "$SOUND_ENDPOINT_RE" $RESULTS \
            | sort -k1n \
            | cut -f2- \
            > $SMOKE_OUTPUT
        column -t $SMOKE_OUTPUT -s $'\t'
    fi

    if grep -q "\[\*\]" $RESULTS; then
        echo
        echo "  [*]  Indicates one or more work-arounds were deployed."
    fi
} > $REPORT


sendEmail() { # $1 - email address, $2 - subject
    ## Rename the file because the filename is used as the attachment's name
    FAILURES2=/tmp/smoke-test-details-$date.txt
    cp $FAILURES $FAILURES2
    FILES_TO_DELETE="$FILES_TO_DELETE $FAILURES2"

    case $MAILER in
        mail)
            mail -s "$2" "$1" -A $FAILURES2 < $REPORT
            ;;

        thunderbird)
            thunderbird -compose "subject='$2',to='$1',message='$REPORT',attachment='$FAILURES2'"

            ## Unfortunately, the 'thunderbird' command returns
            ## straight away and only reads any attachments when
            ## sending the email.  Since this script will delete the
            ## temporary files on exit, we must wait here until
            ## thunderbird has sent the email.
            echo "Press ENTER when email is sent."
            read
            ;;

        *)
            echo "Unknown mailer '$MAILER'"
            ;;
    esac
}


voms-proxy-info -e >/dev/null 2>&1 || fatal "Need valid X.509 proxy"
voms-proxy-info -e -hours 1 >/dev/null 2>&1 || fatal "X.509 proxy expires too soon"
voms-proxy-info --acexists dteam 2>/dev/null || fatal "X.509 proxy does not assert dteam membership"

echo "Building report for ${OUTPUT_DESCRIPTION}..."
runTests
buildReport

if [ -n "$sendEmail" ]; then
    echo "Sending email to $sendEmail"
    date=$(date --iso-8601=m)
    sendEmail "$sendEmail" "Smoke test report $date"
else
    cat $REPORT
    echo
    cat $FAILURES
fi
