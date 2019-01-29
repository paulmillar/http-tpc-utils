#!/bin/bash
#
#  Simple tests to verify endpoint is ready
#

THIRDPARTY_UNAUTHENTICATED_URL=https://prometheus.desy.de:2443/Video/BlenderFoundation/Sintel.webm
THIRDPARTY_PRIVATE_URL=https://prometheus.desy.de:2443/VOs/dteam/private-file
THIRDPARTY_UPLOAD_BASE_URL=https://prometheus.desy.de:2443/VOs/dteam

RESET="\e[0m"
GREEN="\e[32m"
RED="\e[31m"

fail() {
    echo -e "$RED$@$RESET"
    exit 1
}

success() {
    echo -e "${GREEN}SUCCESS${RESET}"
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

CURL_BASE="curl -s -f -L --capath /etc/grid-security/certificates"
CURL_X509="$CURL_BASE -E $PROXY"

FILE_URL=$URL/smoke-test-$(uname -n)-$$

echo "Target: $FILE_URL"
echo
echo "DIRECT TRANSFER TESTS"
echo
echo -n "Uploading to target with X.509 authn: "
$CURL_X509 -T /bin/bash -o /dev/null $FILE_URL || fail "Upload failed" && success

echo -n "Downloading from target with X.509 authn: "
$CURL_X509 -o/dev/null $FILE_URL || fail "Download failed" && success

echo -n "Deleting target with X.509 authn: "
$CURL_X509 -X DELETE $FILE_URL || fail "Delete failed" && success

echo -n "Request DOWNLOAD,UPLOAD,DELETE macaroon from target: "
tmp=$(mktemp)
$CURL_X509 -# -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD,UPLOAD,DELETE"]}' $FILE_URL | jq -r .macaroon > $tmp || fail "Macaroon request failed." && success
TARGET_MACAROON=$(cat $tmp)
rm -f $tmp

CURL_MACAROON="$CURL_BASE -H \"Authorization: bearer $TARGET_MACAROON\""

echo -n "Uploading to target with macaroon authz: "
eval $CURL_MACAROON -T /bin/bash -o/dev/null $FILE_URL || fail "Upload failed" && success

echo -n "Downloading from target with macaroon authz: "
eval $CURL_MACAROON -o/dev/null $FILE_URL || fail "Download failed" && success

echo -n "Deleting target with macaroon authz: "
eval $CURL_MACAROON -X DELETE $FILE_URL || fail "Delete failed" && success

echo
echo "THIRD-PARTY PULL TESTS"
echo

echo "Initiating an unauthenticated HTTP PULL, authn with X.509 to target"
$CURL_X509 -X COPY -H 'Credential: none' -H "Source: $THIRDPARTY_UNAUTHENTICATED_URL" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed" && (echo -n "Third-party copy: "; success)

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE $FILE_URL || fail "Delete failed" && success

echo "Initiating an unauthenticated HTTP PULL, authz with macaroon to target"
eval $CURL_MACAROON -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed" && (echo -n "Third-party copy: "; success)

echo -n "Deleting target with macaroon: "
eval $CURL_MACAROON -# -X DELETE $FILE_URL || fail "Delete failed" && success

echo -n "Requesting DOWNLOAD macaroon for private file:"
tmp=$(mktemp)
$CURL_X509 -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD"]}' $THIRDPARTY_PRIVATE_URL | jq -r .macaroon > $tmp || fail "Macaroon request failed." && success
THIRDPARTY_DOWNLOAD_MACAROON=$(cat $tmp)
rm -f $tmp

echo "Initiating a macaroon authz HTTP PULL, authn with X.509 to target"
$CURL_X509 -X COPY -H 'Credential: none' -H "TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON" -H "Source: $THIRDPARTY_PRIVATE_URL" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed" && (echo -n "Third-party copy: "; success)

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE $FILE_URL || fail "Delete failed" && success

echo "Initiating a macaroon authz HTTP PULL, authz with macaroon to target"
eval $CURL_MACAROON -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\" -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed" && (echo -n "Third-party copy: "; success)

echo -n "Deleting target with macaroon: "
eval $CURL_MACAROON -X DELETE $FILE_URL || fail "Delete failed" && success

echo
echo "THIRD-PARTY PUSH TESTS"
echo

THIRDPARTY_UPLOAD_URL=$THIRDPARTY_UPLOAD_BASE_URL/smoke-test-push-$(uname -n)-$$

echo "Third-party push target: $THIRDPARTY_UPLOAD_URL"
echo
echo -n "Requesting UPLOAD macaroon to third-party push target: "
tmp=$(mktemp)
$CURL_X509 -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:UPLOAD"]}' $THIRDPARTY_UPLOAD_URL | jq -r .macaroon > $tmp || fail "Macaroon request failed." && success
THIRDPARTY_UPLOAD_MACAROON=$(cat $tmp)
rm -f $tmp

echo -n "Uploading target, authn with X.509: "
$CURL_X509 -T /bin/bash -o /dev/null $FILE_URL || fail "Upload failed" && success

echo "Initiating a macaroon authz HTTP PUSH, authn with X.509 to target"
$CURL_X509 -X COPY -H 'Credential: none' -H "TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON" -H "Destination: $THIRDPARTY_UPLOAD_URL" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed"  && (echo -n "Third-party copy: "; success)

echo -n "Deleting file pushed to third-party, with X.509: "
$CURL_X509 -X DELETE $THIRDPARTY_UPLOAD_URL || fail "Delete failed" && success

echo "Initiating a macaroon authz HTTP PUSH, authz with macaroon to target"
eval $CURL_MACAROON -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\" -H \"Destination: $THIRDPARTY_UPLOAD_URL\" $FILE_URL | sed -e 's/^/     /' || fail "Copy failed" && (echo -n "Third-party copy: "; success)

echo -n "Deleting file pushed to third-party, with X.509: "
$CURL_X509 -X DELETE $THIRDPARTY_UPLOAD_URL || fail "Delete failed" && success

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE $FILE_URL || fail "Delete failed" && success

