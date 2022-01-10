#!/usr/bin/env python3
#
# Parse a WebDAV door's access log file to calculate the concurrency
# of COPY requests.
#
# Minimal example usage:
#
#     bin/concurrency.py webdav-door.access >concurrency.dat
#
# For more details, see help:
#
#     bin/concurrency.py --help

import argparse
import re
import dateutil.parser
import datetime
import sys

parser = argparse.ArgumentParser(description=""" Parse WebDAV access log file to determine the COPY request.  The
output is a data file that describes the period represented by the
access log file.  That period is binned into specific time periods
(e.g., every five minutes).  For each time period, the minimum,
average and maximum number of concurrent COPY requests is recorded.
""")
parser.add_argument('filename', metavar='FILE',
                    help='the path to the access log file.')
parser.add_argument('--period', metavar='PERIOD', type=float, default="300",
                    help='the number of seconds in each time bin.')
parser.add_argument('--exclude_before', metavar='TIMESTAMP', type=dateutil.parser.isoparse,
                    help='do not consider any COPY operations that finish before TIMESTAMP.')
parser.add_argument('--exclude_after', metavar='TIMESTAMP', type=dateutil.parser.isoparse,
                    help='do not consider any COPY operations that start after TIMESTAMP.')
args = parser.parse_args()

pat = re.compile(r'''([^\s=]+)=(?:"([^"]*)"|([^\s]*))''')

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def reduce_attrib(attr):
    if attr[1]:
        return (attr[0],attr[1])
    else:
        return (attr[0],attr[2])

def build_attr_map(line):
    re_matches = pat.findall(line)
    key_value_pairs = [reduce_attrib(attr) for attr in re_matches]
    return dict((k, v) for k, v in key_value_pairs)

def build_events_from_line(line):
    attr = build_attr_map(line)
    if attr["request.method"] != "COPY":
        return []

    end_time = dateutil.parser.isoparse(attr["ts"])

    if args.exclude_before and end_time < args.exclude_before:
        return []

    duration = datetime.timedelta(milliseconds=int(attr["duration"]))
    start_time = end_time - duration

    if args.exclude_after and start_time > args.exclude_after:
        return []

    return [(start_time, "START"), (end_time, "END")]


def min_concurrency(events):
    c = 0
    min_c = 0
    for ts,event in events:
        if event == "START":
            c += 1
        if event == "END":
            c -= 1
        if c < min_c:
            min_c = c
    return c


def build_events_from_file(file):
    eprint("Loading {}...".format(file.name))
    events = []
    line_number = 0
    for line in file:
        line_number += 1
        if line_number % 100000 == 0:
            eprint("    {} lines so far".format(line_number))
        events.extend(build_events_from_line(line))

    eprint("Sorting {} events...".format(len(events)))
    return sorted(events, key=lambda tup: tup[0])

def round_down_time(date, delta):
    seconds_in_hour = date.minute * 60 + date.second
    updated_seconds_in_hour = int(delta * int(seconds_in_hour / delta))
    delta_seconds = seconds_in_hour - updated_seconds_in_hour
    return (date - datetime.timedelta(seconds=delta_seconds)).replace(microsecond=0)


def should_print(timebin_start,timebin_end):
    return (not args.exclude_before or timebin_start >= args.exclude_before) \
        and \
        (not args.exclude_after or timebin_end <= args.exclude_after)


with open(args.filename,'r') as f:
    events = build_events_from_file(f)

    # Work-around for log file being incomplete and missing START events.
    eprint("Evaluating minimum concurrency...")
    c = -min_concurrency(events)

    first_event = events[0][0]

    timebin_start = round_down_time(first_event,args.period)
    last_event = timebin_start
    timebin_end = timebin_start + datetime.timedelta(seconds=args.period)
    (min,max) = (c,c)
    avr = 0
    eprint("Building output...")
    for ts,event in events:
        delta = ts - last_event
        bins = int((ts - timebin_start).total_seconds() / args.period)

        while bins > 0:
            delta_to_next_bin=timebin_end - last_event
            avr += delta_to_next_bin.total_seconds() * c
            if should_print(timebin_start, timebin_end):
                print("{} {} {} {}".format(timebin_end, min, avr/args.period, max))
            (min,max) = (c,c)
            delta -= delta_to_next_bin
            avr = 0
            timebin_start = timebin_end
            timebin_end += datetime.timedelta(seconds=args.period)
            last_event = timebin_start
            bins -= 1

        avr += delta.total_seconds() * c

        if event == "START":
            c += 1
            if (c > max):
                max = c

        if event == "END":
            c -= 1
            if (c < min):
                min = c

        last_event = ts
