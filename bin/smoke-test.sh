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
extended=0

fail() {
    if [ -z "$lastTestFailed" -o "$lastTestFailed" == "0" ]; then
        error="$@"
    else
        error="$(curlRcMessage)"
    fi

    if [ -f "$VERBOSE" ]; then
        statusLine="$(sed -n 's/\* The requested URL returned error: //p' $VERBOSE | tail -1)"
        if [ "$statusLine" != "" ]; then
            error="$statusLine"
        fi
    fi

    local errorSuffix=
    if [ "$NON_SUT_TEST" == "1" ]; then
        errorSuffix=" (doesn't count)"
    fi

    echo -e "$RESET${RED}FAILED: $error$RESET$errorSuffix"
    if [ -f "$VERBOSE" -a $fullRun -eq 0 ]; then
        echo -e "\nThe curl command that failed:"
        echo -e "\n    $TEST_COMMAND"
        echo -e "\nVerbose output from curl:"
        awk '{if ($0 ~ /HTTP\/1.1/){colour="\x1B[0m"}else{colour="\x1B[2m"}print "    "colour$0}' < $VERBOSE
        echo -e "$RESET"
    fi
    if [ $fullRun -eq 0 ]; then
        exit 1
    fi
    if [ "$NON_SUT_TEST" != "1" ]; then
        FAILED=$(( $FAILED + 1 ))
    fi
}

fatal() {
    fail "$@"
    exit 1
}

success() {
    local suffix=
    if [ "$NON_SUT_TEST" == "1" ]; then
        suffix=" (doesn't count)"
    fi

    echo -e "${GREEN}SUCCESS$RESET${suffix}"
    rm -f $VERBOSE
    if [ "$NON_SUT_TEST" != "1" ]; then
        SUCCESSFUL=$(( $SUCCESSFUL + 1 ))
    fi
}

skipped() {
    local suffix=
    if [ "$NON_SUT_TEST" == "1" ]; then
        suffix=" (doesn't count)"
    fi

    echo -e "$RESET${YELLOW}SKIPPED: $@$RESET$suffix"
    if [ "$NON_SUT_TEST" != "1" ]; then
        SKIPPED=$(( $SKIPPED + 1 ))
    fi
}

cleanup() {
    rm -f $FILES_TO_DELETE
    echo -e "$RESET"
}

curlRcMessage() {
    case $lastTestFailed in
        0)
            echo "Success."
            ;;
        1)
            echo "Unsupported protocol."
            ;;
        2)
            echo "Failed to initialize."
            ;;
        3)
            echo "URL malformed. The syntax was not correct."
            ;;
        4)
            echo "A feature or option is not available."
            ;;
        5)
            echo "Couldn't resolve proxy"
            ;;
        6)
            echo "Couldn't resolve host"
            ;;
        7)
            echo "Failed to connect to host."
            ;;
        8)
            echo "Weird server reply."
            ;;
        9)
            echo "FTP access denied."
            ;;
        11|13)
            echo "FTP weird PASS reply."
            ;;
        14)
            echo "FTP weird 227 format."
            ;;
        15)
            echo "FTP can't get host."
            ;;
        17)
            echo "FTP couldn't set binary."
            ;;
        18)
            echo "Partial file."
            ;;
        19)
            echo "RETR (or similar) command failed."
            ;;
        21)
            echo "FTP quote error."
            ;;
        22)
            echo "HTTP  page  not  retrieved."
            ;;
        23)
            echo "Write error."
            ;;
        25)
            echo "FTP couldn't STOR file."
            ;;
        26)
            echo "Read error."
            ;;
        27)
            echo "Out of memory."
            ;;
        28)
            echo "Operation timeout."
            ;;
        30)
            echo "FTP PORT failed."
            ;;
        31)
            echo "FTP couldn't use REST."
            ;;
        33)
            echo "HTTP range error."
            ;;
        34)
            echo "HTTP post error."
            ;;
        35)
            echo "SSL connect error."
            ;;
        36)
            echo "FTP bad download resume."
            ;;
        37)
            echo "FILE couldn't read file."
            ;;
        38)
            echo "LDAP cannot bind."
            ;;
        39)
            echo "LDAP search failed."
            ;;
        41)
            echo "LDAP function not found."
            ;;
        42)
            echo "Aborted by callback."
            ;;
        43)
            echo "Function was called with a bad parameter."
            ;;
        45)
            echo "Outgoing interface could not be used."
            ;;
        47)
            echo "Too many redirects."
            ;;
        48)
            echo "Unknown option specified to libcurl."
            ;;
        49)
            echo "Malformed telnet option."
            ;;
        51)
            echo "The peer's SSL certificate or SSH MD5 fingerprint was not OK."
            ;;
        52)
            echo "The server didn't reply anything."
            ;;
        53)
            echo "SSL crypto engine not found."
            ;;
        54)
            echo "Cannot set SSL crypto engine as default."
            ;;
        55)
            echo "Failed sending network data."
            ;;
        56)
            echo "Failure in receiving network data."
            ;;
        58)
            echo "Problem with the local certificate."
            ;;
        59)
            echo "Couldn't use specified SSL cipher."
            ;;
        60)
            echo "Peer certificate cannot be authenticated with known CA certificates."
            ;;
        61)
            echo "Unrecognized transfer encoding."
            ;;
        62)
            echo "Invalid LDAP URL."
            ;;
        63)
            echo "Maximum file size exceeded."
            ;;
        64)
            echo "Requested FTP SSL level failed."
            ;;
        65)
            echo "Sending the data requires a rewind that failed."
            ;;
        66)
            echo "Failed to initialise SSL Engine."
            ;;
        67)
            echo "Failed to log in."
            ;;
        68)
            echo "File not found on TFTP server."
            ;;
        69)
            echo "Permission problem on TFTP server."
            ;;
        70)
            echo "Out of disk space on TFTP server."
            ;;
        71)
            echo "Illegal TFTP operation."
            ;;
        72)
            echo "Unknown TFTP transfer ID."
            ;;
        73)
            echo "File already exists (TFTP)."
            ;;
        74)
            echo "No such user (TFTP)."
            ;;
        75)
            echo "Character conversion failed."
            ;;
        76)
            echo "Character conversion functions required."
            ;;
        77)
            echo "Problem with reading the SSL CA cert."
            ;;
        78)
            echo "The resource referenced in the URL does not exist."
            ;;
        79)
            echo "An unspecified error occurred during the SSH session."
            ;;
        80)
            echo "Failed to shut down the SSL connection."
            ;;
        82)
            echo "Could not load CRL file."
            ;;
        83)
            echo "Issuer check failed."
            ;;
        84)
            echo "The FTP PRET command failed."
            ;;
        85)
            echo "RTSP: mismatch of CSeq numbers."
            ;;
        86)
            echo "RTSP: mismatch of Session Identifiers."
            ;;
        87)
            echo "unable to parse FTP file list."
            ;;
        88)
            echo "FTP chunk callback reported error."
            ;;
        89)
            echo "No connection available, the session will be queued."
            ;;
        90)
            echo "SSL public key does not matched pinned public key."
            ;;
        *)
            echo "Unknown code: $lastTestFailed"
    esac
}

checkResult() {
    lastTestFailed=$?
    if [ $lastTestFailed -eq 0 ]; then
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
    local rc=$?

    if [ $rc -ne 0 ]; then
        lastTestFailed=$rc
        fail "$1"
    fi

    shift

    for var in "$@"; do
        eval $var=$lastTestFailed
    done
}

checkHeader() { # $1 - error if cmd fails, $2 - RE for headers, $3 error if RE doesn't match
    local rc=$?
    if [ $rc -ne 0 ]; then
       lastTestFailed=$rc
       fail "$1"
    else
       grep -q "$2" $HEADERS
       checkResult "$3"
    fi
}

#  Simple wrapper around a curl invocation that "remembers" the
#  command-line.
doCurl() {
    TEST_COMMAND=$(eval echo "$@")
    eval "$@"
}

runCopy() {
    if [ $fullRun -eq 1 ]; then
        echo -n ": "
        doCurl "$@" 2>$VERBOSE >$COPY_OUTPUT
        lastTestFailed=$?
    else
        echo -e -n "...\n$DIM"
        doCurl "$@" 2>$VERBOSE | tee $COPY_OUTPUT
        lastTestFailed=$?

        # Insert newline if server COPY didn't include one (xrootd)
        c=$(tail -c 1 $COPY_OUTPUT)
        [ "$c" != "" ] && echo

        echo -e -n "${RESET}Third party copy: "
    fi

    if [ $lastTestFailed -ne 0 ]; then
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

#  Like requestMacaroon but success or failure does not count towards
#  endpoint's score.
requestRemoteMacaroon() { # $1 Caveats, $2 URL, $3 variable for macaroon, $4 variable for result
    NON_SUT_TEST=1
    requestMacaroon "$1" "$2" "$3" "$4"
    unset NON_SUT_TEST
}

requestMacaroon() { # $1 Caveats, $2 URL, $3 variable for macaroon, $4 variable for result
    local target_macaroon=$(mktemp)
    local macaroon_json=$(mktemp)
    local macaroon
    FILES_TO_DELETE="$FILES_TO_DELETE $target_macaroon $macaroon_json"

    lastTestFailed=0

    doCurl $CURL_X509 -m$MACAROON_TIMEOUT -X POST -H \'Content-Type: application/macaroon-request\' -d \'{\"caveats\": [\"activity:$1\"], \"validity\": \"PT30M\"}\' -o$macaroon_json $2 2>$VERBOSE
    checkFailure "Macaroon request failed." $4
    if [ $lastTestFailed -eq 0 ]; then
        jq -r .macaroon $macaroon_json >$target_macaroon
        checkFailure "Badly formatted JSON" $4
    fi
    if [ $lastTestFailed -eq 0 ]; then
        macaroon="$(cat $target_macaroon)"
        [ "$macaroon" != "null" ]
        checkResult "Missing 'macaroon' element" $4
    fi

    eval $3="$macaroon"
}

for dependency in curl jq awk voms-proxy-info dig; do
    type $dependency >/dev/null || fatal "Missing dependency \"$dependency\".  Please install a package that provides this command."
done

while getopts "h?fx" opt; do
    case "$opt" in
        h|\?)
            echo "$0 [-f] [-x] URL"
            echo
            echo "  -f  Do not stop on first error"
            echo "  -x  Run additional tests"
            exit 0
            ;;
        f)
            fullRun=1
            ;;
        x)
            extended=1
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

CURL_BASE="curl --verbose --connect-timeout $CONNECT_TIMEOUT -D $HEADERS -s -f -L --capath /etc/grid-security/certificates \$CURL_ADDRESS_SELECTION $CURL_EXTRA_OPTIONS"
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

IPv4_ADDRESSES=$(dig +short $HOST A | grep '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*$')
IPv6_ADDRESSES=$(dig +short $HOST AAAA | grep '^[0-9a-f:]*$')
ALL_IP_ADDRESSES="$IPv4_ADDRESSES $IPv6_ADDRESSES"
IP_ADDRESS_COUNT=$(echo "$ALL_IP_ADDRESSES" | wc -w)

if [ $IP_ADDRESS_COUNT -eq 0 ]; then
   echo "WARNING: Failed to resolve any IP addresses for $HOST"
fi

macaroonFailed=1
IP_ADDRESS_COUNTER=1
for IP_ADDRESS in $ALL_IP_ADDRESSES; do

    if [ $IP_ADDRESS_COUNT -gt 1 ]; then
        [ $IP_ADDRESS_COUNTER -ne 1 ] && echo
        echo "Checking $IP_ADDRESS ($IP_ADDRESS_COUNTER of $IP_ADDRESS_COUNT)"
        echo
        unset IP_FAMILY
        echo $IP_ADDRESS | grep -q '\.' && IP_FAMILY="ipv4" || IP_FAMILY="ipv6"
        if [ $IP_FAMILY = "ipv6" ]; then
            IP_ADDRESS="[${IP_ADDRESS}]"
        fi
        CURL_ADDRESS_SELECTION="--$IP_FAMILY --connect-to $HOST:$PORT:$IP_ADDRESS:$PORT"
        IP_ADDRESS_COUNTER=$(( $IP_ADDRESS_COUNTER + 1 ))
    fi

    echo -n "Uploading to target with X.509 authn: "
    doCurl $CURL_X509 $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "Upload failed" uploadFailed
    [ $uploadFailed -ne 0 ] && eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state

    echo -n "Downloading from target with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
        doCurl $CURL_X509 $MUST_MAKE_PROGRESS -o/dev/null $FILE_URL 2>$VERBOSE
        checkResult "Download failed"
    else
        skipped "upload failed"
    fi

    echo -n "Obtaining ADLER32 checksum via RFC 3230 HEAD request with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
        doCurl $CURL_X509 -I -H \"Want-Digest: adler32\" -o/dev/null $FILE_URL 2>$VERBOSE
        checkHeader "HEAD request failed" '^Digest: adler32' "No Digest header"
    else
        skipped "upload failed"
    fi

    if [ $extended -ne 0 ]; then
        echo -n "Obtaining ADLER32 or MD5 checksum via RFC 3230 HEAD request with X.509 authn: "
        if [ $uploadFailed -ne 0 ]; then
            skipped "upload failed"
        else
            doCurl $CURL_X509 -I -H \"Want-Digest: adler32,md5\" -o/dev/null $FILE_URL 2>$VERBOSE
            checkHeader "HEAD request failed" '^Digest: \(adler32\|md5\)' "No Digest header"
        fi

        echo -n "Obtaining ADLER32 checksum via RFC 3230 GET request with X.509 authn: "
        if [ $uploadFailed -ne 0 ]; then
            skipped "upload failed"
        else
            doCurl $CURL_X509 -H \"Want-Digest: adler32\" -o/dev/null $FILE_URL 2>$VERBOSE
            checkHeader "HEAD request failed" '^Digest: adler32' "No Digest header"
        fi

        echo -n "Obtaining ADLER32 or MD5 checksum via RFC 3230 GET request with X.509 authn: "
        if [ $uploadFailed -ne 0 ]; then
            skipped "upload failed"
        else
            doCurl $CURL_X509 -H \"Want-Digest: adler32,md5\" -o/dev/null $FILE_URL 2>$VERBOSE
            checkHeader "HEAD request failed" '^Digest: \(adler32\|md5\)' "No Digest header"
        fi
    fi

    echo -n "Deleting target with X.509 authn: "
    if [ $uploadFailed -eq 0 ]; then
        doCurl $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
        checkResult "Delete failed"
    else
        skipped "upload failed"
    fi

    activityList="DOWNLOAD,UPLOAD,DELETE"
    activityList="$activityList,LIST"   # DPM requires LIST for an RFC-3230 HEAD requests
    echo -n "Request $activityList macaroon from target: "
    requestMacaroon $activityList $FILE_URL THIS_ADDR_TARGET_MACAROON thisAddrMacaroonFailed

    if [ $thisAddrMacaroonFailed -eq 0 ]; then
        macaroonFailed=0
        TARGET_MACAROON="$THIS_ADDR_TARGET_MACAROON"
    fi

    CURL_MACAROON="$CURL_BASE -H \"Authorization: Bearer $TARGET_MACAROON\"" # NB. StoRM requires "Bearer" not "bearer"

    echo -n "Uploading to target with macaroon authz: "
    if [ $macaroonFailed -eq 0 ]; then
        doCurl $CURL_MACAROON $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
        checkResult "Upload failed" uploadFailed
        [ $uploadFailed -ne 0 ] && eval $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state
    else
        skipped "no macaroon"
    fi

    echo -n "Downloading from target with macaroon authz: "
    if [ $macaroonFailed -ne 0 ]; then
        skipped "no macaroon"
    elif [ $uploadFailed -ne 0 ]; then
        skipped "upload failed"
    else
        doCurl $CURL_MACAROON $MUST_MAKE_PROGRESS -o/dev/null $FILE_URL 2>$VERBOSE
        checkResult "Download failed"
    fi

    echo -n "Obtaining ADLER32 checksum via RFC 3230 HEAD request with macaroon authz: "
    if [ $macaroonFailed -ne 0 ]; then
        skipped "no macaroon"
    elif [ $uploadFailed -ne 0 ]; then
        skipped "upload failed"
    else
        doCurl $CURL_MACAROON -I -H \"Want-Digest: adler32\" -o/dev/null $FILE_URL 2>$VERBOSE
        checkHeader "HEAD request failed" '^Digest: adler32' "No Digest header"
    fi

    echo -n "Deleting target with macaroon authz: "
    if [ $macaroonFailed -ne 0 ]; then
        skipped "no macaroon"
    elif [ $uploadFailed -ne 0 ]; then
        skipped "upload failed"
    else
        doCurl $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL  2>$VERBOSE
        checkResult "Delete failed"
    fi

done

unset CURL_ADDRESS_SELECTION

echo
echo "THIRD PARTY PULL TESTS"
echo

echo -n "Initiating an unauthenticated HTTP PULL, authn with X.509 to target"
runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL

echo -n "Deleting target with X.509: "
if [ $lastTestFailed -ne 0 ]; then
    skipped "upload failed"
else
    doCurl $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success
fi

echo -n "Initiating an unauthenticated HTTP PULL, authz with macaroon to target"
if [ $macaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no macaroon"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL
fi

echo -n "Deleting target with macaroon: "
if [ $macaroonFailed -ne 0 ]; then
    skipped "no macaroon"
elif [ $lastTestFailed -ne 0 ]; then
    skipped "upload failed"
else
    doCurl $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success
fi

echo -n "Requesting (from prometheus) DOWNLOAD macaroon for a private file: "
requestRemoteMacaroon DOWNLOAD $THIRDPARTY_PRIVATE_URL THIRDPARTY_DOWNLOAD_MACAROON tpcDownloadMacaroonFailed

echo -n "Initiating a macaroon authz HTTP PULL, authn with X.509 to target"
if [ $tpcDownloadMacaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no TPC macaroon"
else
    runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \'TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\' -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL
fi

echo -n "Deleting target with X.509: "
if [ $tpcDownloadMacaroonFailed -ne 0 ]; then
    skipped "no TPC macaroon"
elif [ $lastTestFailed -ne 0 ]; then
    skipped "third-party transfer failed"
else
    doCurl $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult
fi

echo -n "Initiating a macaroon authz HTTP PULL, authz with macaroon to target"
if [ $macaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no macaroon"
elif [ $tpcDownloadMacaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no TPC macaroon"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\" -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL
fi

echo -n "Deleting target with macaroon: "
if [ $macaroonFailed -ne 0 ]; then
    skipped "no macaroon"
elif [ $tpcDownloadMacaroonFailed -ne 0 ]; then
    skipped "no TPC macaroon"
elif [ $lastTestFailed -ne 0 ]; then
    skipped "third-party transfer failed"
else
    doCurl $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult
fi

echo
echo "THIRD PARTY PUSH TESTS"
echo

THIRDPARTY_UPLOAD_URL=$THIRDPARTY_UPLOAD_BASE_URL/smoke-test-push-$(uname -n)-$$

echo "Third party push target: $THIRDPARTY_UPLOAD_URL"
echo

echo -n "Requesting (from prometheus) UPLOAD,DELETE macaroon to third party push target: "
requestRemoteMacaroon UPLOAD,DELETE $THIRDPARTY_UPLOAD_URL THIRDPARTY_UPLOAD_MACAROON tpcUploadMacaroonFailed

echo -n "Uploading target, authn with X.509: "
if [ $tpcUploadMacaroonFailed -ne 0 ]; then
    skipped "no third-party macaroon"
else
    doCurl $CURL_X509 $MUST_MAKE_PROGRESS -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "Upload failed" sourceUploadFailed
    [ $sourceUploadFailed -ne 0 ] && eval $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>/dev/null # Clear any stale state
fi

echo -n "Initiating a macaroon authz HTTP PUSH, authn with X.509 to target"
if [ $tpcUploadMacaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -ne 0 ]; then
    echo -n ": "
    skipped "source upload failed"
else
    runCopy $CURL_X509 $ENFORCE_TPC_TIMEOUT -X COPY -H \'TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\' -H \'Destination: $THIRDPARTY_UPLOAD_URL\' $FILE_URL
fi

echo -n "Deleting file pushed to third party, with X.509: "
if [ $tpcUploadMacaroonFailed -ne 0 ]; then
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -ne 0 ]; then
    skipped "source upload failed"
elif [ $lastTestFailed -ne 0 ]; then
    skipped "push failed"
else
    doCurl $CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE
    checkResult "delete failed"
fi

echo -n "Initiating a macaroon authz HTTP PUSH, authz with macaroon to target"
if [ $macaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no macaroon"
elif [ $tpcUploadMacaroonFailed -ne 0 ]; then
    echo -n ": "
    skipped "no third-party macaroon"
elif [ $sourceUploadFailed -ne 0 ]; then
    echo -n ": "
    skipped "source upload failed"
else
    runCopy $CURL_MACAROON $ENFORCE_TPC_TIMEOUT -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\" -H \"Destination: $THIRDPARTY_UPLOAD_URL\" $FILE_URL
fi

echo -n "Deleting file pushed to third party, with X.509: "
if [ $macaroonFailed -ne 0 ]; then
    skipped "no macaroon"
elif [ $tpcUploadMacaroonFailed -ne 0 ]; then
    skipped "no TPC macaroon"
elif [ $sourceUploadFailed -ne 0 ]; then
    skipped "source upload failed"
elif [ $lastTestFailed -ne 0 ]; then
    skipped "push failed"
else
    doCurl $CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE
    checkResult "delete failed"
fi

echo -n "Deleting target with X.509: "
if [ $tpcUploadMacaroonFailed -ne 0 ]; then
    skipped "no TPC UPLOAD macaroon"
elif [ $sourceUploadFailed -ne 0 ]; then
    skipped "source upload failed"
else
    doCurl $CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE
    checkResult "delete failed"
fi

if [ $fullRun -eq 1 ]; then
    TOTAL=$(( $SUCCESSFUL + $FAILED + $SKIPPED ))
    ATTEMPTED=$(( $SUCCESSFUL + $FAILED ))
    echo
    echo -n "Of $TOTAL tests: "
    if [ $SKIPPED -ne 0 ]; then
        echo -n "$SKIPPED skipped"
        if [ $SKIPPED -ne $TOTAL ]; then
            echo -n " ("
            echo -n "$(printf "%.0f" $(( 100 * $SKIPPED / $TOTAL )) )%"
            echo -n ")"
        fi

        echo -n ", $ATTEMPTED attempted"
        echo -n " ("
        echo -n "$(printf "%.0f" $(( 100 * $ATTEMPTED / $TOTAL )) )%"
        echo -n "): "
    fi
    echo -n "$SUCCESSFUL successful"
    if [ $SUCCESSFUL -ne 0 ]; then
        echo -n " ("
        echo -n "$(printf "%.0f" $(( 100 * $SUCCESSFUL / $ATTEMPTED )) )%"
        if [ $ATTEMPTED -ne $TOTAL ]; then
            echo -n " of tests run, $(printf "%.0f" $(( 100 * $SUCCESSFUL / $TOTAL )) )% of all tests"
        fi
        echo -n ")"
    fi
    if [ $FAILED -ne 0 ]; then
        echo -n ", $FAILED failed"
        if [ $FAILED -ne $TOTAL ]; then
            echo -n " ("
            echo -n "$(printf "%.0f" $(( 100 * $FAILED / $ATTEMPTED )) )%"
            if [ $ATTEMPTED -ne $TOTAL ]; then
                echo -n " of tests run, $(printf "%.0f" $(( 100 * $FAILED / $TOTAL )) )% of all tests"
            fi
            echo -n ")"
        fi
    fi
fi

rc=0
[ $SKIPPED -gt 0 ] && rc=2
[ $FAILED -gt 0 ] && rc=1
exit $rc
