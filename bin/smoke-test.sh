#!/bin/bash
#
#  Simple tests to verify endpoint is ready for DOMA-TPC
#

THIRDPARTY_UNAUTHENTICATED_URL=https://prometheus.desy.de:2443/Video/BlenderFoundation/Sintel.webm
THIRDPARTY_PRIVATE_URL=https://prometheus.desy.de:2443/VOs/dteam/private-file
THIRDPARTY_UPLOAD_BASE_URL=https://prometheus.desy.de:2443/VOs/dteam

RESET="\e[0m"
DIM="\e[2m"
GREEN="\e[32m"
RED="\e[31m"

fail() {
    echo -e "$RESET$RED$@$RESET"
    if [ -f "$VERBOSE" ]; then
        echo -e "\nVerbose output from curl:"
	awk '{if ($0 ~ /HTTP\/1.1/){colour="\x1B[0m"}else{colour="\x1B[2m"}print "    "colour$0}' < $VERBOSE
	echo -e "$RESET"
    fi
    exit 1
}

success() {
    echo -e "${GREEN}SUCCESS$RESET"
    rm -f $VERBOSE
}

cleanup() {
    rm -f $FILES_TO_DELETE
    echo -e "$RESET"
}

for dependency in curl jq awk voms-proxy-info; do
    type $dependency >/dev/null || fail "Missing dependency \"$dependency\".  Please install a package that provides this command."
done

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


VERBOSE=$(mktemp)
FILES_TO_DELETE=$VERBOSE
trap cleanup EXIT

CURL_BASE="curl --verbose -s -f -L --capath /etc/grid-security/certificates"
CURL_X509="$CURL_BASE -E $PROXY"

FILE_URL=$URL/smoke-test-$(uname -n)-$$

echo
echo "Target: $FILE_URL"
echo
echo "DIRECT TRANSFER TESTS"
echo
echo -n "Uploading to target with X.509 authn: "
$CURL_X509 -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE || fail "Upload failed" && success

echo -n "Downloading from target with X.509 authn: "
$CURL_X509 -o/dev/null $FILE_URL 2>$VERBOSE || fail "Download failed" && success

echo -n "Deleting target with X.509 authn: "
$CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

echo -n "Request DOWNLOAD,UPLOAD,DELETE macaroon from target: "
tmp=$(mktemp)
FILES_TO_DELETE="$FILES_TO_DELETE $tmp"
$CURL_X509 -# -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD,UPLOAD,DELETE"]}' $FILE_URL  2>$VERBOSE | jq -r .macaroon >$tmp || fail "Macaroon request failed." && success
TARGET_MACAROON=$(cat $tmp)

CURL_MACAROON="$CURL_BASE -H \"Authorization: bearer $TARGET_MACAROON\""

echo -n "Uploading to target with macaroon authz: "
eval $CURL_MACAROON -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE || fail "Upload failed" && success

echo -n "Downloading from target with macaroon authz: "
eval $CURL_MACAROON -o/dev/null $FILE_URL 2>$VERBOSE || fail "Download failed" && success

echo -n "Deleting target with macaroon authz: "
eval $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL  2>$VERBOSE || fail "Delete failed" && success

echo
echo "THIRD PARTY PULL TESTS"
echo

echo "Initiating an unauthenticated HTTP PULL, authn with X.509 to target..."
echo -e -n "$DIM"
$CURL_X509 -X COPY -H 'Credential: none' -H "Source: $THIRDPARTY_UNAUTHENTICATED_URL" $FILE_URL 2>$VERBOSE || fail "Copy failed" && (echo -e -n "${RESET}Third party copy: "; success)

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

echo "Initiating an unauthenticated HTTP PULL, authz with macaroon to target..."
echo -e -n "$DIM"
eval $CURL_MACAROON -X COPY -H \"Source: $THIRDPARTY_UNAUTHENTICATED_URL\" $FILE_URL 2>$VERBOSE || fail "Copy failed" && (echo -e -n "${RESET}Third party copy: "; success)

echo -n "Deleting target with macaroon: "
eval $CURL_MACAROON -# -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

echo -n "Requesting DOWNLOAD macaroon for private file: "
tmp=$(mktemp)
FILES_TO_DELETE="$FILES_TO_DELETE $tmp"
$CURL_X509 -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:DOWNLOAD"]}' $THIRDPARTY_PRIVATE_URL 2>$VERBOSE | jq -r .macaroon > $tmp || fail "Macaroon request failed." && success
THIRDPARTY_DOWNLOAD_MACAROON=$(cat $tmp)

echo "Initiating a macaroon authz HTTP PULL, authn with X.509 to target..."
echo -e -n "$DIM"
$CURL_X509 -X COPY -H 'Credential: none' -H "TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON" -H "Source: $THIRDPARTY_PRIVATE_URL" $FILE_URL 2>$VERBOSE || fail "Copy failed" && (echo -e -n "${RESET}Third party copy: "; success)

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

echo "Initiating a macaroon authz HTTP PULL, authz with macaroon to target..."
echo -e -n "$DIM"
eval $CURL_MACAROON -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_DOWNLOAD_MACAROON\" -H \"Source: $THIRDPARTY_PRIVATE_URL\" $FILE_URL 2>$VERBOSE || fail "Copy failed" && (echo -e -n "${RESET}Third party copy: "; success)

echo -n "Deleting target with macaroon: "
eval $CURL_MACAROON -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

echo
echo "THIRD PARTY PUSH TESTS"
echo

THIRDPARTY_UPLOAD_URL=$THIRDPARTY_UPLOAD_BASE_URL/smoke-test-push-$(uname -n)-$$

echo "Third party push target: $THIRDPARTY_UPLOAD_URL"
echo
echo -n "Requesting UPLOAD macaroon to third party push target: "
tmp=$(mktemp)
FILES_TO_DELETE="$FILES_TO_DELETE $tmp"
$CURL_X509 -X POST -H 'Content-Type: application/macaroon-request' -d '{"caveats": ["activity:UPLOAD"]}' $THIRDPARTY_UPLOAD_URL 2>$VERBOSE | jq -r .macaroon > $tmp || fail "Macaroon request failed." && success
THIRDPARTY_UPLOAD_MACAROON=$(cat $tmp)

echo -n "Uploading target, authn with X.509: "
$CURL_X509 -T /bin/bash -o/dev/null $FILE_URL 2>$VERBOSE || fail "Upload failed" && success

echo "Initiating a macaroon authz HTTP PUSH, authn with X.509 to target..."
echo -e -n "$DIM"
$CURL_X509 -X COPY -H 'Credential: none' -H "TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON" -H "Destination: $THIRDPARTY_UPLOAD_URL" $FILE_URL 2>$VERBOSE || fail "Copy failed"  && (echo -e -n "${RESET}Third party copy: "; success)

echo -n "Deleting file pushed to third party, with X.509: "
$CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE || fail "Delete failed" && success

echo "Initiating a macaroon authz HTTP PUSH, authz with macaroon to target..."
echo -e -n "$DIM"
eval $CURL_MACAROON -X COPY -H \"TransferHeaderAuthorization: bearer $THIRDPARTY_UPLOAD_MACAROON\" -H \"Destination: $THIRDPARTY_UPLOAD_URL\" $FILE_URL 2>$VERBOSE || fail "Copy failed" && (echo -e -n "Third party copy: "; success)

echo -n "Deleting file pushed to third party, with X.509: "
$CURL_X509 -X DELETE -o/dev/null $THIRDPARTY_UPLOAD_URL 2>$VERBOSE || fail "Delete failed" && success

echo -n "Deleting target with X.509: "
$CURL_X509 -X DELETE -o/dev/null $FILE_URL 2>$VERBOSE || fail "Delete failed" && success

