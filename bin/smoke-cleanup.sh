#!/bin/bash

SHARE=$(cd $(dirname $0)/../share;pwd)

fatal() {
    echo "$@"
    exit 1
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
[ $? -ne 0 ] && fatal "PROPFIND failed"

FILES=$(xsltproc --stringparam path $URL_PATH $SHARE/list-files.xsl $TMP_FILE | grep smoke-test)
rm $TMP_FILE

if [ $? -eq 0 ]; then
    for file in $FILES; do
	FILE_URL=$URL/$file
	echo Removing $FILE_URL
	curl -s -E /tmp/x509up_u1000 --capath /etc/grid-security/certificates -X DELETE $FILE_URL
    done
fi
