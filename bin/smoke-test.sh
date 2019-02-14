#!/bin/bash
#
#  Simple tests to verify endpoint is ready for DOMA-TPC
#

THIRDPARTY_UNAUTHENTICATED_URL=https://prometheus.desy.de:2443/Video/BlenderFoundation/Sintel.webm
THIRDPARTY_PRIVATE_URL=https://prometheus.desy.de:2443/VOs/dteam/private-file
THIRDPARTY_UPLOAD_BASE_URL=https://prometheus.desy.de:2443/VOs/dteam

CONNECT_TIMEOUT=60  # value in seconds

## Drop transfer if average bandwidth over SPEED_TIME is less than
## SPEED_LIMIT.
##
SPEED_TIME=15       # value in seconds
SPEED_LIMIT=1024    # value in bytes per second

## Total time allowed for a macaroon request to complete.
##
MACAROON_TIMEOUT=30 # value in seconds

## Total time allowed for a third-party transfer to complete.
##
TPC_TIMEOUT=600     # value in seconds

RESET="\e[0m"
DIM="\e[2m"
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"

SUCCESSFUL=0
FAILED=0
SKIPPED=0

fullRun=0

fail() {
    error="$@"
    if [ -f "$VERBOSE" ]; then
	statusLine="$(sed -n 's/\* The requested URL returned error: //p' $VERBOSE | tail -1)"
	if [ "$statusLine" != "" ]; then
	    error="$statusLine"
	fi
    fi
    echo -e "$RESET${RED}FAILED: $error$RESET"
    if [ -f "$VERBOSE" -a $fullRun -eq 0 ]; then
        echo -e "\nVerbose output from curl:"
	awk '{if ($0 ~ /HTTP\/1.1/){colour="\x1B[0m"}else{colour="\x1B[2m"}print "    "colour$0}' < $VERBOSE
	echo -e "$RESET"
    fi
    if [ $fullRun -eq 0 ]; then
	exit 1
    fi
    lastTestFailed=1
    FAILED=$(( $FAILED + 1 ))
}

fatal() {
    fail "$@"
    exit 1
}

success() {
    echo -e "${GREEN}SUCCESS$RESET"
    rm -f $VERBOSE
    lastTestFailed=0
    SUCCESSFUL=$(( $SUCCESSFUL + 1 ))
}

skipped() {
    echo -e "$RESET${YELLOW}SKIPPED: $@$RESET"
    SKIPPED=$(( $SKIPPED + 1 ))
}

cleanup() {
    rm -f $FILES_TO_DELETE
    echo -e "$RESET"
}

checkResult() {
    if [ $? -eq 0 ]; then
	success
    else
	fail "$1"
    fi

    shift

    for var in "$@"; do
	eval $var=$lastTestFailed
    done
}

checkFailure() {
    if [ $? -ne 0 ]; then
	fail "$1"
    fi

    shift

    for var in "$@"; do
	eval $var=$lastTestFailed
    done
}

checkHeader() { # $1 - error if cmd fails, $2 - RE for headers, $3 error if RE doesn't match
    if [ $? -ne 0 ]; then
       fail "$1"
    else
       grep -q "$2" $HEADERS
       checkResult "$3"
    fi
}

runCopy() {
    if [ $fullRun -eq 1 ]; then
	echo -n ": "
	eval "$@" 2>$VERBOSE >$COPY_OUTPUT
    else
	echo -e -n "...\n$DIM"
	eval "$@" 2>$VERBOSE | tee $COPY_OUTPUT

        # Insert newline if server COPY didn't include one (xrootd)
	c=$(tail -c 1 $COPY_OUTPUT)
	[ "$c" != "" ] && echo

	echo -e -n "${RESET}Third party copy: "
    fi

    if [ $? -ne 0 ]; then
	fail "COPY request failed"
    else
	lastLine="$(tail -1 $COPY_OUTPUT)"

	# REVISIT: shouldn't this be standardised?
	if [ "${lastLine#success}" != "${lastLine}" ]; then
	    success
	elif [ "${lastLine#Success}" != "${lastLine}" ]; then # for DPM compatibility
	    success
	elif [ "${lastLine#failure:}" != "${lastLine}" ]; then
	    fail "${lastLine#failure:}"
	else
	    fail "for an unknown reason"
	fi
    fi
}


requestMacaroon() { # $1 Caveats, $2 URL, $3 target variable
    local target_macaroon=$(mktemp)
    local macaroon_json=$(mktemp)
    local macaroon
    FILES_TO_DELETE="$FILES_TO_DELETE $target_macaroon $macaroon_json"

    lastTestFailed=0

    eval $CURL_X509 -m$MACAROON_TIMEOUT -X POST -H \'Content-Type: application/macaroon-request\' -d \'{\"caveats\": [\"activity:$1\"], \"validity\": \"PT30M\"}\' -o$macaroon_json $2 2>$VERBOSE
    checkFailure "Macaroon request failed." $4
    if [ $lastTestFailed -eq 0 ]; then
	jq -r .macaroon $macaroon_json >$target_macaroon
	checkFailure "Badly formatted JSON" $4
    fi
    if [ $lastTestFailed -eq 0 ]; then
	macaroon="$(cat $target_macaroon)"
	[ "$TARGET_MACAROON" != "null" ]
	checkResult "Missing 'macaroon' element" $4
    fi

    eval $3="$macaroon"
}

for dependency in curl jq awk voms-proxy-info dig; do
    type $dependency >/dev/null || fatal "Missing dependency \"$dependency\".  Please install a package that provides this command."
done

while getopts "h?f" opt; do
    case "$opt" in
	h|\?)
	    echo "$0 [-f] URL"
	    echo
	    echo "-f  Do not stop on first error"
	    exit 0
	    ;;
	f)
	    fullRun=1
	    ;;
    esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift

if [ $# -ne 1 ]; then
    fatal "Need exactly one argument: the webdav endpoint; e.g., https://webdav.example.org:2881/path/to/dir"
fi

if [ "${1#https://}" = "$1" ]; then
    fatal "URL must start https://"
fi

URL=${1%/}
WITHOUT_SCHEME=${URL#https://}
HOST_PORT=$(echo $WITHOUT_SCHEME | cut -d '/' -f1)
HOST=$(echo $HOST_PORT | cut -d ':' -f1)
if [ "$HOST" = "$HOST_PORT" ]; then
    PORT=443
else
    PORT=${HOST_PORT#$HOST:}
fi

voms-proxy-info -e >/dev/null 2>&1 || fatal "Need valid X.509 proxy"
voms-proxy-info --acexists dteam 2>/dev/null || fatal "X.509 proxy does not assert dteam membership"

PROXY=/tmp/x509up_u$(id -u)


VERBOSE=$(mktemp)
HEADERS=$(mktemp)
COPY_OUTPUT=$(mktemp)
FILES_TO_DELETE="$VERBOSE $COPY_OUTPUT $HEADERS"
trap cleanup EXIT

CURL_BASE="curl --verbose --connect-timeout $CONNECT_TIMEOUT -D $HEADERS -s -f -L --capath /etc/grid-security/certificates $CURL_EXTRA_OPTIONS"
CURL_BASE="$CURL_BASE -H 'X-No-Delegate: true'"  # Tell DPM not to request GridSite delegation.
CURL_BASE="$CURL_BASE --location-trusted"        # SLAC xrootd redirects, expecting re-authentication.
CURL_X509="$CURL_BASE --cacert $PROXY -E $PROXY"
CURL_X509="$CURL_X509 -H 'Credential: none'"     # Tell dCache not to request GridSite delegation.

MUST_MAKE_PROGRESS="--speed-time $SPEED_TIME --speed-limit $SPEED_LIMIT"
ENFORCE_TPC_TIMEOUT="-m $TPC_TIMEOUT"

FILE_URL=$URL/smoke-test-$(uname -n)-$$

if [ -n "$DNS_SERVER" ]; then
    DIG_OPTIONS="@$DNS_SERVER"
fi

echo
echo "Target: $FILE_URL"
echo
echo "DIRECT TRANSFER TESTS"
echo

ALL_IP_ADDRESSES=$(dig $DIG_OPTIONS $HOST | awk '/ANSWER SECTION:/,/^$/{print $5}' | sort | uniq)
IP_ADDRESS_COUNT=$(echo "$ALL_IP_ADDRESSES" | wc -w)

IP_ADDRESS_COUNTER=1
for IP_ADDRESS in $ALL_IP_ADDRESSES; do

    if [ $IP_ADDRESS_COUNT -gt 1 ]; then
	[ $IP_ADDRESS_COUNTER -ne 1 ] && echo
	echo "Checking $IP_ADDRESS ($IP_ADDRESS_COUNTER of $IP_ADDRESS_COUNT)"
	echo
	CURL_TARGET="--connect-to $HOST:$PORT:$IP_ADDRESS:$PORT"
	IP_ADDRESS_COUNTER=$(( $IP_ADDRESS_COUNTER + 1 ))
    fi

    echo -n "Uploading to target with X.509 authn: "
    eval $CURL_X509 $CURL_TARGET $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "Upload failed" uploadFailed
    [ $uploadFailed -eq 1 ] && eval $CURL_X509 $CURL_TARGET -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state

    echo -n "Downloading from target with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
	eval $CURL_X509 $CURL_TARGET $MUST_MAKE_PROGRESS -o/dev/null $FILE_URL 2>$VERBOSE
	checkResult "Download failed"
    else
	skipped "upload failed"
    fi

    echo -n "Obtaining ADLER32 checksum via RFC 3230 HEAD request with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
	eval $CURL_X509 $CURL_TARGET -I -H \"Want-Digest: adler32\" -o/dev/null $FILE_URL 2>$VERBOSE
	checkHeader "HEAD request failed" '^Digest: adler32' "No Digest header"
    else
	skipped "upload failed"
    fi

    echo -n "Obtaining ADLER32 or MD5 checksum via RFC 3230 HEAD request with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
	eval $CURL_X509 $CURL_TARGET -I -H \"Want-Digest: adler32,md5\" -o/dev/null $FILE_URL 2>$VERBOSE
	checkHeader "HEAD request failed" '^Digest: \(adler32\|md5\)' "No Digest header"
    else
	skipped "upload failed"
    fi

    echo -n "Deleting target with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
	eval $CURL_X509 $CURL_TARGET -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
	checkResult "Delete failed"
    else
	skipped "upload failed"
    fi

    echo -n "Request DOWNLOAD,UPLOAD,DELETE macaroon from target: "
    requestMacaroon DOWNLOAD,UPLOAD,DELETE $FILE_URL TARGET_MACAROON macaroonFailed

    CURL_MACAROON="$CURL_BASE $CURL_TARGET -H \"Authorization: Bearer $TARGET_MACAROON\"" # NB. StoRM requires "Bearer" not "bearer"

    echo -n "Uploading to target with macaroon authz: "
    if [ $macaroonFailed -eq 0 ]; then
	eval $CURL_MACAROON $CURL_TARGET $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
	checkResult "Upload failed" uploadFailed
	[ $uploadFailed -eq 1 ] && eval $CURL_MACAROON $CURL_TARGET -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state
    else
	skipped "no macaroon"
    fi

    echo -n "Downloading from target with macaroon authz: "
    if [ $macaroonFailed -eq 1 ]; then
	skipped "no macaroon"
    elif [ $uploadFailed -eq 1 ]; then
	skipped "upload failed"
    else
	eval $CURL_MACAROON $CURL_TARGET $MUST_MAKE_PROGRESS -o/dev/null $FILE_URL 2>$VERBOSE
	checkResult "Download failed"
    fi

    echo -n "Obtaining ADLER32 checksum via RFC 3230 HEAD request with macaroon authz: "
    if [ $macaroonFailed -eq 1 ]; then
	skipped "no macaroon"
    elif [ $uploadFailed -eq 1 ]; then
	skipped "upload failed"
    else
	eval $CURL_MACAROON $CURL_TARGET -I -H \"Want-Digest: adler32\" -o/dev/null $FILE_URL 2>$VERBOSE
	checkHeader "HEAD request failed" '^Digest: adler32' "No Digest header"
    fi

    echo -n "Obtaining ADLER32 or MD5 checksum via RFC 3230 HEAD request with macaroon authz: "
    if [ $macaroonFailed -eq 1 ]; then
	skipped "no macaroon"
    elif [ $uploadFailed -eq 1 ]; then
	skipped "upload failed"
    else
	eval $CURL_MACAROON $CURL_TARGET -I -H \"Want-Digest: adler32,md5\" -o/dev/null $FILE_URL 2>$VERBOSE
	checkHeader "HEAD request failed" '^Digest: \(adler32\|md5\)' "No Digest header"
    fi

    echo -n "Deleting target with macaroon authz: "
    if [ $macaroonFailed -eq 1 ]; then
	skipped "no macaroon"
    elif [ $uploadFailed -eq 1 ]; then
	skipped "upload failed"
    else
	eval $CURL_MACAROON $CURL_TARGET -X DELETE -o/dev/null $FILE_URL  2>$VERBOSE
	checkResult "Delete failed"
    fi

done

echo
echo "THIRD PARTY PULL TESTS"
echo

echo -n "Initiating an unauthenticated HTTP PULL, authn with X.509 to target"
runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL

echo -n "Deleting target with X.509: "
if [ $lastTestFailed -eq 1 ]; then
    skipped "upload failed"
else
    eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success
fi

echo -n "Initiating an unauthenticated HTTP PULL, authz with macaroon to target"
if [ $macaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no macaroon"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL
fi

echo -n "Deleting target with macaroon: "
if [ $macaroonFailed -eq 1 ]; then
    skipped "no macaroon"
elif [ $lastTestFailed -eq 1 ]; then
    skipped "upload failed"
else
    eval $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success
fi

echo -n "Requesting (from prometheus) DOWNLOAD macaroon for a private file: "
requestMacaroon DOWNLOAD $THIRDPARTY_PRIVATE_URL THIRDPARTY_DOWNLOAD_MACAROON tpcDownloadMacaroonFailed

echo -n "Initiating a macaroon authz HTTP PULL, authn with X.509 to target"
if [ $tpcDownloadMacaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no TPC macaroon"
else
    runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \'TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\' -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL
fi

echo -n "Deleting target with X.509: "
if [ $tpcDownloadMacaroonFailed -eq 1 ]; then
    skipped "no TPC macaroon"
elif [ $lastTestFailed -eq 1 ]; then
    skipped "third-party transfer failed"
else
    eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult
fi

echo -n "Initiating a macaroon authz HTTP PULL, authz with macaroon to target"
if [ $macaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no macaroon"
elif [ $tpcDownloadMacaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no TPC macaroon"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\" -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL
fi

echo -n "Deleting target with macaroon: "
if [ $macaroonFailed -eq 1 ]; then
    skipped "no macaroon"
elif [ $tpcDownloadMacaroonFailed -eq 1 ]; then
    skipped "no TPC macaroon"
elif [ $lastTestFailed -eq 1 ]; then
    skipped "third-party transfer failed"
else
    eval $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult
fi

echo
echo "THIRD PARTY PUSH TESTS"
echo

THIRDPARTY_UPLOAD_URL=$THIRDPARTY_UPLOAD_BASE_URL/smoke-test-push-$(uname -n)-$$

echo "Third party push target: $THIRDPARTY_UPLOAD_URL"
echo

echo -n "Requesting (from prometheus) UPLOAD,DELETE macaroon to third party push target: "
requestMacaroon UPLOAD,DELETE $THIRDPARTY_UPLOAD_URL THIRDPARTY_UPLOAD_MACAROON tpcUploadMacaroonFailed

echo -n "Uploading target, authn with X.509: "
if [ $tpcUploadMacaroonFailed -eq 1 ]; then
    skipped "no third-party macaroon"
else
    eval $CURL_X509 $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "Upload failed" sourceUploadFailed
    [ $sourceUploadFailed -eq 1 ] && eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state
fi

echo -n "Initiating a macaroon authz HTTP PUSH, authn with X.509 to target"
if [ $tpcUploadMacaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -eq 1 ]; then
    echo -n ": "
    skipped "source upload failed"
else
    runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \'TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\' -H \'Destination: $THIRDPARTY_UPLOAD_URL\' $FILE_URL
fi

echo -n "Deleting file pushed to third party, with X.509: "
if [ $tpcUploadMacaroonFailed -eq 1 ]; then
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -eq 1 ]; then
    skipped "source upload failed"
elif [ $lastTestFailed -eq 1 ]; then
    skipped "push failed"
else
    eval $CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE
    checkResult "delete failed"
fi

echo -n "Initiating a macaroon authz HTTP PUSH, authz with macaroon to target"
if [ $macaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no macaroon"
elif [ $tpcUploadMacaroonFailed -eq 1 ]; then
    echo -n ": "
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -eq 1 ]; then
    echo -n ": "
    skipped "source upload failed"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\" -H \"Destination: $THIRDPARTY_UPLOAD_URL\" $FILE_URL
fi

echo -n "Deleting file pushed to third party, with X.509: "
if [ $macaroonFailed -eq 1 ]; then
    skipped "no macaroon"
elif [ $tpcUploadMacaroonFailed -eq 1 ]; then
    skipped "no TPC macaroon"
elif [ $sourceUploadFailed -eq 1 ]; then
    skipped "source upload failed"
elif [ $lastTestFailed -eq 1 ]; then
    skipped "push failed"
else
    eval $CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE
    checkResult "delete failed"
fi

echo -n "Deleting target with X.509: "
if [ $tpcUploadMacaroonFailed -eq 1 ]; then
    skipped "no TPC UPLOAD macaroon"
elif [ $sourceUploadFailed -eq 1 ]; then
    skipped "source upload failed"
else
    eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "delete failed"
fi

if [ $fullRun -eq 1 ]; then
    echo
    echo -n "$(( $SUCCESSFUL + $FAILED )) tests completed: $SUCCESSFUL successful"
    if [ $FAILED -gt 0 -o $SKIPPED -gt 0 ]; then
	echo -n " ("
	echo -n "$(printf "%.0f" $(( 100 * $SUCCESSFUL / ( $SUCCESSFUL + $FAILED ) )) )% of tests run"
	echo -n ", $(printf "%.0f" $(( 100 * $SUCCESSFUL / ( $SUCCESSFUL + $FAILED + $SKIPPED ) )) )% of possible tests"
	echo -n ")"
    fi
    echo -n ", $FAILED failed, $SKIPPED skipped"
fi

rc=0
[ $SKIPPED -gt 0 ] && rc=2
[ $FAILED -gt 0 ] && rc=1
exit $rc
