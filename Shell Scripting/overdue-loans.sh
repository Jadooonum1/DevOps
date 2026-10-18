#!/usr/bin/env bash
# overdue-loans.sh - read a loans CSV and list every book that is past its
# due date, with the number of days late and the fine owed.
#
# Author: Parth Agarwal
#
# CSV format (header line required):
#   loan_id,member,title,due_date      (due_date is YYYY-MM-DD)
#
# Usage:
#   ./overdue-loans.sh sample-data/loans.csv
#   TODAY=2026-10-18 FINE_PER_DAY=5 ./overdue-loans.sh sample-data/loans.csv
#
# Exit codes: 0 = nothing overdue, 1 = overdue loans found, 2 = usage/input error

set -euo pipefail

FINE_PER_DAY=${FINE_PER_DAY:-2}          # rupees per day late
TODAY=${TODAY:-$(date +%F)}              # override for repeatable runs

die() { echo "error: $*" >&2; exit 2; }

to_epoch_day() {
    # GNU date: convert YYYY-MM-DD to days since 1970-01-01
    local secs
    secs=$(date -d "$1" +%s 2>/dev/null) || return 1
    echo $(( secs / 86400 ))
}

[[ $# -eq 1 ]] || die "usage: $0 <loans.csv>"
loans_file=$1
[[ -r $loans_file ]] || die "cannot read '$loans_file'"

today_day=$(to_epoch_day "$TODAY") || die "TODAY='$TODAY' is not a valid date"

overdue=0
total_fine=0

printf '%-6s %-10s %-32s %-10s %5s %6s\n' "LOAN" "MEMBER" "TITLE" "DUE" "LATE" "FINE"

# skip the header with tail, split fields on commas
while IFS=, read -r loan_id member title due; do
    [[ -z $loan_id ]] && continue
    if ! due_day=$(to_epoch_day "$due"); then
        echo "warning: loan $loan_id has a bad due date '$due', skipped" >&2
        continue
    fi

    days_late=$(( today_day - due_day ))
    if (( days_late > 0 )); then
        fine=$(( days_late * FINE_PER_DAY ))
        printf '%-6s %-10s %-32.32s %-10s %5d %6d\n' \
            "$loan_id" "$member" "$title" "$due" "$days_late" "$fine"
        overdue=$(( overdue + 1 ))
        total_fine=$(( total_fine + fine ))
    fi
done < <(tail -n +2 "$loans_file")

echo
echo "As of $TODAY: $overdue overdue loan(s), total fines Rs $total_fine (Rs $FINE_PER_DAY/day)"

(( overdue == 0 ))   # exit 0 only when nothing is overdue
