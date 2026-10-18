# Shell Scripting

**Author:** Parth Agarwal

## Goal

Write a Bash script that reports on the server hosting the `bookshelf` library catalogue:
print date, host and user, show disk usage and running processes, read input from the user,
create a directory and file, and redirect command output into that file.

A second, smaller script (`overdue-loans.sh`) practises loops, functions, arithmetic,
conditionals and exit codes on a CSV of book loans.

## Files

| File | Purpose |
|---|---|
| `library-report.sh` | main assignment script (system summary + saved process report) |
| `overdue-loans.sh` | extra: lists overdue loans and fines from a CSV |
| `sample-data/loans.csv` | test data for `overdue-loans.sh` (one row has a deliberately invalid date) |

## Requirements -> where they are in `library-report.sh`

| Requirement | Implementation |
|---|---|
| Variables | `run_date`, `server`, `operator`, `kernel`, `root_disk`, `process_total`, `report_dir`, `report_name`, `report_path` |
| Command substitution | `$(date ...)`, `$(hostname)`, `$(whoami)`, `$(df -h / \| awk ...)` |
| Date, hostname, user | printed in the summary block with `printf` for aligned columns |
| Disk usage | `df -h` (skipping tmpfs/overlay noise) and a one-line root summary via `awk` |
| Running processes | process count + top 5 by memory with `ps -eo ... --sort=-%mem` |
| User input | two `read -r -p` prompts, with defaults via `${var:-default}` |
| Create directory | `mkdir -p "$report_dir"` (safe to re-run) |
| Create file | `touch "$report_path"` |
| Output redirection | `{ ... } > file` writes a header (truncate), then `ps aux >> file` appends |
| Function | `section()` prints the boxed headings |

Design choices:

- Every expansion is double-quoted, so folder names with spaces work.
- `set -u` makes a typo in a variable name fail loudly instead of expanding to empty.
- If two arguments are given the prompts are skipped (`./library-report.sh nightly run.txt`),
  so the same script can run from cron or CI.
- `>` vs `>>`: the header uses `>` so each run starts a clean file; the process table is appended
  with `>>` underneath it.

## `overdue-loans.sh` in short

- Reads `loan_id,member,title,due_date` rows with `while IFS=, read -r ...`, skipping the header
  with `tail -n +2`.
- Converts dates to "days since epoch" with GNU `date -d` inside a function and compares them
  with `$(( ))` arithmetic.
- Bad rows go to stderr as warnings and are skipped; usage errors exit `2`.
- Exit status is `1` if anything is overdue, `0` otherwise - so it can gate a cron job or a CI step.
- `TODAY` and `FINE_PER_DAY` can be overridden through the environment for repeatable runs.

GNU `date -d` is Linux-specific; on macOS run it in a container (below) or install `coreutils`.

## How to run

```bash
cd "Shell Scripting"
chmod +x library-report.sh overdue-loans.sh
bash -n library-report.sh && bash -n overdue-loans.sh     # syntax check only

./library-report.sh                    # answer the two prompts, e.g. reports / processes.txt
ls -l reports/ && head -n 8 reports/processes.txt && wc -l reports/processes.txt

./library-report.sh nightly run.txt    # non-interactive form

TODAY=2026-10-18 ./overdue-loans.sh sample-data/loans.csv; echo "exit=$?"
```

Run both inside Ubuntu without installing anything locally:

```bash
docker run --rm -it -h bookshelf-srv -v "$PWD":/work -w /work ubuntu:24.04 bash
```

## Tested output

Both scripts were tested in an `ubuntu:24.04` container (hostname `bookshelf-srv`), answering
the prompts with `reports` and `processes.txt`. Real output, trimmed:

```text
------------------------------------------------------------
  bookshelf server report
------------------------------------------------------------
Date:          2026-10-18 13:55:09 UTC
Server:        bookshelf-srv
Operator:      root
Kernel:        Linux 6.8.0-117-generic
Root disk:     4.9G used / 40G total (14%)
Processes:     5
...
------------------------------------------------------------
  report saved
------------------------------------------------------------
File : reports/processes.txt
Lines: 7
Size : 4.0K
```

A container only has a handful of processes; on a real VM the report will be much longer.
Pressing Enter at both prompts created `library-reports/processes-2026-10-18.txt` (defaults).

```text
$ TODAY=2026-10-18 ./overdue-loans.sh sample-data/loans.csv; echo "exit=$?"
LOAN   MEMBER     TITLE                            DUE         LATE   FINE
L1001  aisha      The Pragmatic Programmer         2026-10-01    17     34
L1003  meera      Designing Data-Intensive Applica 2026-09-20    28     56
L1004  kabir      The Linux Command Line           2026-10-17     1      2

As of 2026-10-18: 3 overdue loan(s), total fines Rs 92 (Rs 2/day)
warning: loan L1006 has a bad due date '2026-13-40', skipped
exit=1
```

Also checked: a CSV with nothing overdue exits `0`; no argument or a missing file prints an
error and exits `2`.

Generated report folders (`reports/`, `library-reports/`, ...) are run-time output - do not commit them.

## Screenshots

`screenshots/` contains only `.gitkeep`. Capture:

| File | What it should show |
|---|---|
| `report-run.png` | `./library-report.sh` summary, disk table, top processes and the two prompts |
| `report-file.png` | `ls -l`, `head` and `wc -l` on the saved report |
| `overdue-loans.png` | `overdue-loans.sh` table, warning line and `exit=1` |
