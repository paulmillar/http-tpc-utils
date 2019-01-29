#!/bin/sh
#
#  Simple tests to verify endpoint is ready
#

fail() {
    echo "$@"
    exit 1
}

if [ $# -ne 1 ]; then
    fail "Need exactly one argument the webdav endpoint"
fi

if [ "${1#https://}" = "$1" ]; then
    fail "URL must start https://"
fi

URL=${1%/}

voms-proxy-info -e >/dev/null 2>&1 || fail "Need valid X.509 proxy"
voms-proxy-info --acexists dteam 2>/dev/null || fail "X.509 proxy does not assert dteam membership"

PROXY=/tmp/x509up_u$(id -u)

CURL="curl -L -E $PROXY --capath /etc/grid-security/certificates"

FILE_URL=$URL/smoke-test-$$

echo "Upload a file: "
$CURL -T /bin/bash -# -o /dev/null $FILE_URL || fail "Upload failed"

echo "Download a file: "
$CURL -# -o /tmp/smoke-$$ $FILE_URL || fail "Download failed"

echo "Delete a file: "
$CURL -# -X DELETE $FILE_URL || fail "Delete failed"
