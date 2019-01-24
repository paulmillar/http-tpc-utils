#!/bin/sh
#
#  "Simple" script to analyse dCache access log file, looking for
#  failed HTTP transfers.
#
#  By default, /var/log/dcache/dCacheDomain.access is analysed;
#  however, any access files (gziped or otherwise) may be analysed by
#  listing the paths as arguments to this script.
#
#  The entries with "HTTP:" indicate an HTTP COPY request that failed
#  when processing the HTTP request, before initiating the transfer.
#
#  The entries with "TPC:" indicate an HTTP COPY request that failed
#  after accepting the request; e.g., the remote server returned an
#  error code.
#
#  The direction of the transfer (push or pull) is indicated by
#  whether the URL is listed as "source" or "destination".
#

if [ $# -eq 0 ]; then
    files=/var/log/dcache/dCacheDomain.access
else
    files="$@"
fi

for file in $files; do
    zgrep COPY "$file" \
        | grep -v INFO \
        | sed 's%.*ts=\([^ T]*\)T\([^ ]*\).*tpc.error="\([^"]*\).*tpc.\(source\|destination\)=[^:]*://\([^/]*\).*%\1 \2 TPC:"\3" \4=\5%' \
        | sed 's%.*ts=\([^ T]*\)T\([^ ]*\).*response.code=\([0-9]*\) response.reason="\([^"]*\)".*tpc.\(source\|destination\)=[^:]*://\([^/]*\).*%\1 \2 HTTP:"\3 \4" \5=\6%'
done

