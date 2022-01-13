#!/bin/bash
#
# Use Gnuplot to generate a plot of COPY concurrency.  The data is the
# output from bin/concurrency.py.
#
# Typical usage:
#
#     bin/plot-concurrency.sh concurrency.dat
#
# The output is SVG and is written as a file where the extension is
# replaced with .svg; for example, 'concurrency.svg' in the above
# example usage:

cd $(dirname $0)/..

function fail() { #
    echo "$@"
    exit 1
}

[ $# -eq 1 ] || fail "Need filename to plot"
[ -f "$1" ] || fail "No such file: $1"

svg_target=${1%.*}.svg
png_target=${1%.*}.png
gnuplot -e "infile=\"$1\"" -e "outfile=\"$svg_target\"" share/plot-concurrency.gnu

echo SVG output written as $svg_target

inkscape -e $png_target $svg_target
convert $png_target -background white -alpha remove -alpha off $png_target

echo PNG output written as $png_target
