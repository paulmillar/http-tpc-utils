#!/bin/sh
#
#  Simple tests to verify endpoint is ready
#

TPC_TEST_SRC_URL=https://prometheus.desy.de:2443/Video/BlenderFoundation/Sintel.webm
TPC_TEST2_SRC_URL=https://prometheus.desy.de:2443/VOs/dteam/private-file

fail() {
    echo "$@"
    exit 1
}

if [ $# -ne 1 ]; then
    fail "Need exactly one argument: the webdav endpoint; e.g., https://webdav.example.org:2881/path/to/dir"
fi

if [ "${1#https://}" = "$1" ]; then
    fail "URL must start https://"
fi

URL=${1%/}

voms-proxy-info -e >/dev/null 2>&1 || fail "Need valid X.509 proxy"
voms-proxy-info --acexists dteam 2>/dev/null || fail "X.509 proxy does not assert dteam membership"

PROXY=/tmp/x509up_u$(id -u)

CURL_BASE="curl -f -L --capath /etc/grid-security/certificates"
CURL_X509="$CURL_BASE -E $PROXY"

FILE_URL=$URL/smoke-test-$$

echo "Upload a file with X.509: "
$CURL_X509 -# -T /bin/bash -o /dev/null $FILE_URL || fail "Upload failed"

echo "Download a file with X.509: "
$CURL_X509 -# -o/dev/null $FILE_URL || fail "Download failed"

echo "Delete a file with X.509: "
$CURL_X509 -# -X DELETE $FILE_URL || fail "Delete failed"

echo "Request DOWNLOAD,UPLOAD,DELETE macaroon from target: "
tmp=$(mktemp)
$CURL_X509 -# -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD,UPLOAD,DELETE"]}' $FILE_URL | jq -r .macaroon > $tmp
MACAROON=$(cat $tmp)
rm -f $tmp

CURL_MACAROON="$CURL_BASE -H \"Authorization: bearer $MACAROON\""

echo "Upload a file with macaroon: "
eval $CURL_MACAROON -# -T /bin/bash -o/dev/null $FILE_URL || fail "Upload failed"

echo "Download a file with macaroon: "
eval $CURL_MACAROON -# -o/dev/null $FILE_URL || fail "Download failed"

echo "Delete a file with macaroon: "
eval $CURL_MACAROON -# -X DELETE $FILE_URL || fail "Delete failed"

echo "Initiating an unauthenticated HTTP pull with X.509: "
$CURL_X509 -X COPY -H 'Credential: none' -H "Source: $TPC_TEST_SRC_URL" $FILE_URL || fail "Copy failed"

echo "Deleting copied file with X.509: "
$CURL_X509 -# -X DELETE $FILE_URL || fail "Delete failed"

echo "Initiating an unauthenticated HTTP pull with macaroon: "
eval $CURL_MACAROON -X COPY -H \"Source: $TPC_TEST_SRC_URL\" $FILE_URL || fail "Copy failed"

echo "Deleting copied file with macaroon: "
eval $CURL_MACAROON -# -X DELETE $FILE_URL || fail "Delete failed"

echo "Requesting DOWNLOAD macaroon for private file"
tmp=$(mktemp)
$CURL_X509 -# -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD"]}' $TPC_TEST2_SRC_URL | jq -r .macaroon > $tmp
REMOTE_MACAROON=$(cat $tmp)
rm -f $tmp

echo "Initiating a bearer-token authz HTTP pull with X.509: "
$CURL_X509 -X COPY -H 'Credential: none' -H "TransferHeaderAuthorization: bearer $REMOTE_MACAROON" -H "Source: $TPC_TEST_SRC_URL" $FILE_URL || fail "Copy failed"

echo "Deleting copied file with X.509: "
$CURL_X509 -# -X DELETE $FILE_URL || fail "Delete failed"

echo "Initiating a bearer-token authz HTTP pull with macaroon: "
eval $CURL_MACAROON -X COPY -H \"TransferHeaderAuthorization: bearer $REMOTE_MACAROON\" -H \"Source: $TPC_TEST_SRC_URL\" $FILE_URL || fail "Copy failed"

echo "Deleting copied file with macaroon: "
eval $CURL_MACAROON -# -X DELETE $FILE_URL || fail "Delete failed"

