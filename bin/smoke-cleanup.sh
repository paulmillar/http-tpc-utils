#!/bin/bash

SHARE=$(cd $(dirname $0)/../share;pwd)

RESET="\x1B[0m"
DIM="\x1B[2m"
GREEN="\x1B[32m"
RED="\x1B[31m"
YELLOW="\x1B[33m"

fatal() {
    echo -e "$RED$@$RESET"
    exit 1
}

log() {
    echo -e "$DIM$@$RESET"
}

activity() {
    echo -e "$YELLOW$@$RESET"
}

success() {
    echo -e "$GREEN$@$RESET"
}

if [ $# -ne 1 ]; then
    fatal "Need exactly one argument: the webdav endpoint; e.g., https://webdav.example.org:2881/path/to/dir"
fi

if [ "${1#https://}" = "$1" ]; then
    fatal "URL must start https://"
fi

URL=${1%/}
URL_PATH="/$(echo ${URL#https://} | cut -d/ -f2-)"

voms-proxy-info -e >/dev/null 2>&1 || fatal "Need valid X.509 proxy"
voms-proxy-info --acexists dteam 2>/dev/null || fatal "X.509 proxy does not assert dteam membership"
TMP_FILE=$(mktemp)
curl -s -E /tmp/x509up_u1000 --capath /etc/grid-security/certificates -X PROPFIND --upload-file - -H "Depth: 1" $URL <<EOF >$TMP_FILE
<?xml version="1.0"?>
<a:propfind xmlns:a="DAV:"><a:prop><a:getlastmodified/><a:creationdate/><a:resourcetype/></a:prop></a:propfind>
EOF
rc=$?
[ $rc -ne 0 ] && fatal "PROPFIND $URL failed (rc=$rc)"

xmllint --noout $TMP_FILE || fatal "PROPFIND $URL returned invalid XML"

FILES=$(xsltproc --stringparam path $URL_PATH $SHARE/list-files.xsl $TMP_FILE)
rc=$?

rm -f $TMP_FILE

[ $rc != 0 ] && fatal "PROPFIND $URL returned XML that xsltproc failed to parse (rc=$rc)"

count=0
for file in $FILES; do
    case $file in
	smoke-test*)
	    FILE_URL=$URL/$file
	    activity Removing $FILE_URL
	    curl -s -E /tmp/x509up_u1000 --capath /etc/grid-security/certificates -X DELETE $FILE_URL
	    count=$(( $count + 1 ))
	    ;;
    esac
done

if [ $count = 0 ]; then
    log "No smoke-test files under $URL"
else
    success "Removed $count files under $URL"
fi
