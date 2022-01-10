set term svg size 1024,768
set output outfile
set style data lines
# Uncomment for lines with symbols ("points")
#set style data linesp
set title "Plot of COPY concurrency in dCache"
set format x "%H:%M:%S\n%Y-%m-%d"
set timefmt "%Y-%m-%d %H:%M:%S+01:00"
set xdata time
plot infile using 1:3:5 with filledcurves lc "skyblue" not, \
    infile using 1:5 t "Maximum" lc "blue", \
    infile using 1:4 t "Average" lc "black", \
    infile using 1:3 t "Minimum" lc "blue"
