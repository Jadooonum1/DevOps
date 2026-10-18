#!/usr/bin/env bash
# library-report.sh - health snapshot of the server that hosts the
# "bookshelf" catalogue. Prints who/where/when, disk and process info,
# then asks where to store a report and writes the full process list there.
#
# Author: Parth Agarwal
#
# Usage:
#   ./library-report.sh                 # interactive, prompts for dir and file name
#   ./library-report.sh reports run.txt # non-interactive, values passed as arguments

set -u

# ---- variables -------------------------------------------------------------
run_date=$(date '+%Y-%m-%d %H:%M:%S %Z')
server=$(hostname)
operator=$(whoami)
kernel=$(uname -sr)
root_disk=$(df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 ")"}')
process_total=$(ps -e --no-headers | wc -l)
divider="------------------------------------------------------------"

section() {
    echo
    echo "$divider"
    echo "  $1"
    echo "$divider"
}

# ---- summary ---------------------------------------------------------------
section "bookshelf server report"
printf '%-14s %s\n' "Date:"      "$run_date"
printf '%-14s %s\n' "Server:"    "$server"
printf '%-14s %s\n' "Operator:"  "$operator"
printf '%-14s %s\n' "Kernel:"    "$kernel"
printf '%-14s %s\n' "Root disk:" "$root_disk"
printf '%-14s %s\n' "Processes:" "$process_total"

section "disk usage (real filesystems only)"
df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null || df -h

section "top 5 processes by memory"
ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 6

# ---- user input ------------------------------------------------------------
# Accept arguments so the script can also run unattended (cron, CI).
if [[ $# -ge 2 ]]; then
    report_dir=$1
    report_name=$2
else
    read -r -p "Folder for the report [library-reports]: " report_dir
    read -r -p "Report file name [processes-$(date +%F).txt]: " report_name
fi
report_dir=${report_dir:-library-reports}
report_name=${report_name:-processes-$(date +%F).txt}
report_path="$report_dir/$report_name"

# ---- create directory + file, then redirect output into it ----------------
mkdir -p "$report_dir"
touch "$report_path"

{
    echo "# bookshelf process report"
    echo "# generated $run_date on $server by $operator"
    echo
} > "$report_path"          # '>' starts the file fresh

ps aux >> "$report_path"    # '>>' appends the full process table

section "report saved"
echo "File : $report_path"
echo "Lines: $(wc -l < "$report_path")"
echo "Size : $(du -h "$report_path" | cut -f1)"
