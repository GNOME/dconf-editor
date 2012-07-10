#!/usr/bin/python

# This script removes branch and/or line coverage data for lines that
# contain a particular substring.
#
# In the interest of "fairness" it removes all branch or coverage data
# when a match is found -- not just negative data.  It is therefore
# likely that running this script will actually reduce the total number
# of lines and branches that are marked as covered (in absolute terms).
#
# This script intentionally avoids checking for errors.  Any exceptions
# will trigger make to fail.
#
# Author: Ryan Lortie <desrt@desrt.ca>

import sys

line_suppress = ['g_assert_not_reached']
branch_suppress = ['g_assert', 'g_return_if_fail', 'g_return_val_if_fail', 'G_DEFINE_TYPE']

def check_suppress(suppressions, source, data):
    line, _, rest = data.partition(',')
    line = int(line) - 1

    assert line < len(source)

    for suppression in suppressions:
        if suppression in source[line]:
            return True

    return False

source = []
for line in sys.stdin:
    line = line[:-1]

    keyword, _, rest = line.partition(':')

    # Source file
    if keyword == 'SF':
        source = file(rest).readlines()

    # Branch coverage data
    elif keyword == 'BRDA':
        if check_suppress(branch_suppress, source, rest):
            continue

    # Line coverage data
    elif keyword == 'DA':
        if check_suppress(line_suppress, source, rest):
            continue

    print line
