#!/bin/bash
#
#  Run smoke-test.sh on all endpoints

cleanup() {
    rm -f $FILES_TO_DELETE
}

fatal() {
    echo "$@"
    exit 1
}

trap cleanup EXIT

BASE=$(cd $(dirname $0)/..;pwd)
SMOKE_OUTPUT=$(mktemp)
RESULTS=$(mktemp)
FAILURES=$(mktemp)
REPORT=$(mktemp)
SKIPPED=$(mktemp)
FILES_TO_DELETE="$SMOKE_OUTPUT $RESULTS $FAILURES $REPORT $SKIPPED"
MAILER=mail
EXTENDED_TESTS=0
CLEAR_LINE="\e[2K"

SOUND_ENDPOINT_RE="successful (100%)"

ENDPOINTS=$BASE/etc/endpoints

OUTPUT_DESCRIPTION="stdout"
QUIET=0
VO="dteam"
while getopts "h?e:s:m:xo:p:qv:S:" opt; do
    case "$opt" in
        h|\?)
            echo "$0 -x [-s <addr> [-m <mailer>]] [-p <file>] [-S <file>] [-o <name>]"
            echo
            echo "    -e <file>    endpoint file (defaults to etc/endpoints)"
            echo "    -s <addr>    send report as an email to <addr>"
            echo "    -m <mailer>  use 'mail' or 'thunderbird' to send email"
            echo "    -x           use extended tests, if supported"
            echo "    -p <file>    use <file> for persistent state"
            echo "    -q           limit output to errors and prompts"
            echo "    -v <VO>      specify the VO to use for the tests"
            echo "    -S <file>    skip endpoints listed in <file>"
            echo "    -o <name>    use token auth from oidc-agent account <name>"
            exit 0
            ;;
        e)
            ENDPOINTS="$OPTARG"
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
        o)
            OIDC_AGENT_ACCOUNT="$OPTARG"
            ;;
        p)
            persistentState="$OPTARG"
            ;;
        q)
            QUIET=1
            ;;
        v)
            VO="$OPTARG"
            ;;
        S)
            MANUAL_SKIP_FILE="$OPTARG"
            [ -f "$MANUAL_SKIP_FILE" ] || fatal No such file $MANUAL_SKIP_FILE
            ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

case $MAILER in
    mail|thunderbird)
        ;;
    *)
        fatal "Unknown mailer '$MAILER'"
        ;;
esac

declare -A ENDPOINT_SCORE
declare -A MANUAL_SKIP
declare -A SOFTWARE_COUNT
declare -A SOFTWARE_TOTAL_SCORE

loadManualSkipped() {
    if [ -f "$MANUAL_SKIP_FILE" ]; then
        local OLD_IFS
        OLD_IFS="$IFS"
        IFS=": "
        while read name why; do
            MANUAL_SKIP[$name]="$why"
        done < $MANUAL_SKIP_FILE
        IFS="$OLD_IFS"
    fi
}

downloadGocDbDowntimeInfo() {
    DOWNTIME_XML=$(mktemp)
    FILES_TO_DELETE="$FILES_TO_DELETE $DOWNTIME_XML"
    curl -s -k 'https://goc.egi.eu/gocdbpi/public/?method=get_downtime&ongoing_only=yes' > $DOWNTIME_XML
}

readPersistentState() {
    local OLD_IFS
    OLD_IFS="$IFS"
    IFS=": "
    while read endpoint score; do
        ENDPOINT_SCORE[$endpoint]=$score
    done
    IFS="$OLD_IFS"
} < $persistentState

writePersistentState() {
    for endpoint in "${!ENDPOINT_SCORE[@]}"; do
        echo ${endpoint}:${ENDPOINT_SCORE[$endpoint]}
    done
} > $persistentState


isEndpointToBeSkipped() { # $1 - name, $2 - endpoint
    local name="$1"
    local without_scheme=${2#https://}
    local host_port=$(echo $without_scheme | cut -d '/' -f1)
    local fqdn=$(echo $host_port | cut -d ':' -f1)

    if [ -n "${MANUAL_SKIP[$name]}" ]; then
        SKIP_REASON="${MANUAL_SKIP[$name]}"
        rc=0
    else
        xmllint --xpath "/results/DOWNTIME[HOSTNAME='$fqdn' and SEVERITY='OUTAGE']" $DOWNTIME_XML >/dev/null 2>&1
        rc=$?

        if [ $rc -eq 0 ]; then
            SKIP_REASON="GOCDB Downtime: $(xsltproc --stringparam fqdn $fqdn share/downtime-description.xsl $DOWNTIME_XML)"
        fi
    fi

    return $rc
}


runTests() {
    local options

    STARTED_AT=$(date +%s)

    TOTAL=$(wc -l $ENDPOINTS|awk '{print $1}')
    COUNT=0
    cat $ENDPOINTS | while read name type workarounds url; do
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

        if [ ! -z "$OIDC_AGENT_ACCOUNT" ]; then
            options="$options -t wlcg -o $OIDC_AGENT_ACCOUNT"
        fi

        if [ ! -z "$VO" ]; then
            options="$options -v $VO"
        fi

        if [[ "$workarounds" == *L* ]]; then
            options="$options -L"
        fi

        if [[ "$workarounds" == *2* ]]; then
            options="$options -2"
        fi

        COUNT=$(( $COUNT + 1 ))

        if isEndpointToBeSkipped $name $url; then
            [ $QUIET -eq 0 ] && echo -n -e "${CLEAR_LINE}Skipping: $name [$COUNT/$TOTAL] $options $url\r"
            echo -e "$name\t$type\t$SKIP_REASON" >> $SKIPPED

        else

            [ $QUIET -eq 0 ] && echo -n -e "${CLEAR_LINE}Testing: $name [$COUNT/$TOTAL] $options $url\r"

            startTime=$(date +%s)
            bin/smoke-test.sh $options $url > $SMOKE_OUTPUT
            result=$?
            elapsedTime=$(( $(date +%s) - $startTime ))
            duration=$(duration $startTime)
            if [ $result -ne 0 ]; then
                [ -s $FAILURES ] && echo -e "\n" >> $FAILURES
                echo $name >> $FAILURES
                head -n-2 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g' | awk '{print "    "$0}' >> $FAILURES
            fi
            testCount=$(sed -n 's/^Of \([0-9]*\) tests.*/\1/p' $SMOKE_OUTPUT)
            testSuccess=$(sed -n 's/^Of [0-9]* tests.*: \([0-9]*\) successful.*/\1/p' $SMOKE_OUTPUT)
            testNonSuccessful=$(( $testCount - $testSuccess ))
            echo -e "$testNonSuccessful\t$name\t$type\t$(tail -1 $SMOKE_OUTPUT | sed -e 's/[[0-9]*m//g')\t[in $duration]" >> $RESULTS
        fi
    done
    [ $QUIET -eq 0 ] && echo -n -e "${CLEAR_LINE}"
}

duration() { # $1 - UNIX time when period started
    local elapsedTime=$(( $(date +%s) - $1 ))
    printf "%02d:%02d" $(($elapsedTime/60)) $(($elapsedTime%60))
}

updateScores() {
    while read ignore endpoint type rest; do
        case $rest in
            *${SOUND_ENDPOINT_RE}*)
                ENDPOINT_SCORE[$endpoint]=$(( ${ENDPOINT_SCORE[$endpoint]} + 1 ))
                if [ ${ENDPOINT_SCORE[$endpoint]} -gt 20 ]; then
                    ENDPOINT_SCORE[$endpoint]=20
                fi
                ;;
            *)
                ENDPOINT_SCORE[$endpoint]=$(( ${ENDPOINT_SCORE[$endpoint]} - 1 ))
                if [ ${ENDPOINT_SCORE[$endpoint]} -lt 0 ]; then
                    ENDPOINT_SCORE[$endpoint]=0
                fi
                ;;
        esac
        SOFTWARE_COUNT[$type]=$(( ${SOFTWARE_COUNT[$type]} + 1 ))
        SOFTWARE_TOTAL_SCORE[$type]=$(( ${SOFTWARE_TOTAL_SCORE[$type]} + ${ENDPOINT_SCORE[$endpoint]} ))
    done < $RESULTS
}

# Function round(precision, number), from
# https://unix.stackexchange.com/questions/265119/how-to-format-floating-point-number-with-exactly-2-significant-digits-in-bash
round() { # $1=sig.fig, $2=value
    n=$(printf "%.${1}g" "$2")
    if [ "$n" != "${n#*e}" ]
    then
        f="${n##*e-}"
        test "$n" = "$f" && f= || f=$(( ${f#0}+$1-1 ))
        printf "%0.${f}f" "$n"
    else
        printf "%s" "$n"
    fi
}

buildReport() {
    UPDATED_RESULTS=$(mktemp)
    HEADER_SOUND=$(mktemp)
    HEADER_PROBLEMATIC=$(mktemp)
    FILES_TO_DELETE="$FILES_TO_DELETE $UPDATED_RESULTS $HEADER_SOUND $HEADER_PROBLEMATIC"

    if [ -n "$persistentState" ]; then
        while read failures endpoint rest; do
            echo -e "${ENDPOINT_SCORE[$endpoint]}\t$endpoint\t$rest"
        done < $RESULTS > $UPDATED_RESULTS
        sort -k1rn $UPDATED_RESULTS > $RESULTS
        echo -e "SCORE\tENDPOINT\tSOFTWARE\tWORK-AROUNDS" > $HEADER_SOUND
        echo -e "SCORE\tENDPOINT\tSOFTWARE\tSUMMARY" > $HEADER_PROBLEMATIC
    else
        sort -k1n $RESULTS | cut -f2- > $UPDATED_RESULTS
        mv $UPDATED_RESULTS $RESULTS
        echo -e "ENDPOINT\tSOFTWARE\tWORK-AROUNDS" > $HEADER_SOUND
        echo -e "ENDPOINT\tSOFTWARE\tSUMMARY" > $HEADER_PROBLEMATIC
    fi


    duration=$(duration $STARTED_AT)
    echo "DOMA-TPC smoke test, started $(date --iso-8601=m -d@$STARTED_AT), took $duration."

    if grep -q "$SOUND_ENDPOINT_RE" $RESULTS; then
        haveSoundEndpoints=1
        echo
        echo "SOUND ENDPOINTS"
        echo
        cp $HEADER_SOUND $SMOKE_OUTPUT
        grep "$SOUND_ENDPOINT_RE" $RESULTS \
            | sed 's/ *Of [0-9]* tests:.*Work-arounds: \([^ \t]*\)/[\1]/' \
            | sed 's/\[(none)\]/ /' \
            >> $SMOKE_OUTPUT
        column -t $SMOKE_OUTPUT -s $'\t'
    fi

    if grep -v -q "$SOUND_ENDPOINT_RE" $RESULTS; then
        if [ "$haveSoundEndpoints" = 1 ]; then
            echo
        fi
        haveProblematicEndpoints=1
        echo
        echo "PROBLEMATIC ENDPOINTS"
        echo
        cp $HEADER_PROBLEMATIC $SMOKE_OUTPUT
        grep -v "$SOUND_ENDPOINT_RE" $RESULTS \
            >> $SMOKE_OUTPUT
        column -t $SMOKE_OUTPUT -s $'\t'
    fi

    if [ -s "$SKIPPED" ]; then
        if [ "$haveSoundEndpoints$haveProblematicEndpoints" != "" ]; then
            echo
        fi

        echo
        echo "SKIPPED ENDPOINTS"
        echo
        if [ -n "$persistentState" ]; then
            echo -e "SCORE\tENDPOINT\tSOFTWARE\tWHY" > $SMOKE_OUTPUT
            while read endpoint rest; do
                echo -e "${ENDPOINT_SCORE[$endpoint]}\t$endpoint\t$rest"
            done < $SKIPPED >> $SMOKE_OUTPUT
        else
            echo -e "ENDPOINT\tSOFTWARE\tWHY" > $SMOKE_OUTPUT
            cat $SKIPPED >> $SMOKE_OUTPUT
        fi
        column -t $SMOKE_OUTPUT -s $'\t'
    fi

    if [ ${#SOFTWARE_COUNT[*]} -gt 0 ]; then
        echo
        echo "SOFTWARE SCORES"
        echo
        for type in "${!SOFTWARE_COUNT[@]}"; do
            count=${SOFTWARE_COUNT[$type]}
            total=${SOFTWARE_TOTAL_SCORE[$type]}
            if [ "$total" = "" ] || [ $count -eq 0 ]; then
                average="-"
            else
                average=$(round 2 $(( $total / $count )) )
            fi
            echo -e "$type\t$count\t$average"
        done | sort > $SMOKE_OUTPUT
        echo -e "SOFTWARE\tENDPOINT COUNT\tAVERAGE SCORE" \
            | cat - $SMOKE_OUTPUT \
            | column -t -s $'\t'
    fi
} > $REPORT


sendEmail() { # $1 - email address, $2 - subject
    local mailer

    ## Rename the file because the filename is used as the attachment's name
    FAILURES2=/tmp/smoke-test-details-$date.txt
    cp $FAILURES $FAILURES2
    FILES_TO_DELETE="$FILES_TO_DELETE $FAILURES2"

    case $MAILER in
        mail)
            mailer=mailx
            mail -V |grep -i mailutils >/dev/null 2>&1 && mailer=mailutils
            case $mailer in
                mailx)
                    mail -s "$2" -a $FAILURES2 "$1" < $REPORT
                    ;;
                mailutils)
                    mail -s "$2" "$1" -A $FAILURES2 < $REPORT
                    ;;
                *)
                    echo "Unknown mailer $mailer"
                    ;;
            esac
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
voms-proxy-info --acexists $VO 2>/dev/null || fatal "X.509 proxy does not assert $VO membership"

loadManualSkipped
downloadGocDbDowntimeInfo

[ -f "$persistentState" ] && readPersistentState

[ $QUIET -eq 0 ] && echo "Building report for ${OUTPUT_DESCRIPTION}..."
runTests

[ -n "$persistentState" ] && updateScores

buildReport

if [ -n "$sendEmail" ]; then
    [ $QUIET -eq 0 ] && echo "Sending email to $sendEmail"
    date=$(date --iso-8601=m -d@$STARTED_AT)
    sendEmail "$sendEmail" "Smoke test report $date"
else
    cat $REPORT
    echo
    cat $FAILURES
fi


[ -n "$persistentState" ] && writePersistentState
