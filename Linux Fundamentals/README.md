# Linux Fundamentals

**Author:** Parth Agarwal

## Goal

Get comfortable with the parts of Linux a DevOps engineer touches every day, using a small
"library catalogue" box as the playground:

1. Hard links vs symbolic links (and what an inode is)
2. `useradd` vs `adduser`
3. Reading service logs with `journalctl`
4. A personal cheat sheet of everyday commands

## Environment

Everything was run in throwaway `ubuntu:24.04` containers from my Mac (Docker Desktop, arm64).
Parts 1, 2 and 4 use a plain container; Part 3 needs `systemd` as PID 1, so it uses a
privileged container (see below).

```bash
docker run --rm -it -h library-lab ubuntu:24.04 bash
```

The outputs pasted below are real, trimmed only where marked. Inode numbers, PIDs and
timestamps will differ on your machine.

---

## Part 1 - Hard links vs symbolic links

### Concept

A filename is only a directory entry that points to an **inode**; the inode holds the
permissions, owner, size and the location of the data blocks.

- A **hard link** is one more directory entry for the *same* inode. All names are equal;
  the data is freed only when the inode's link count reaches 0.
- A **symbolic (soft) link** is a tiny separate file (its own inode) whose content is a *path*.
  If the path stops existing the link "dangles".

| | Hard link | Symbolic link |
|---|---|---|
| Points to | the inode | a path (text) |
| Own inode | no | yes |
| Original deleted | data still reachable | link breaks |
| Across filesystems / partitions | not allowed | allowed |
| To a directory | not allowed | allowed |
| In `ls -l` | looks like a normal file, link count > 1 | `l` type and `-> target` |

### Commands

```bash
mkdir shelf && cd shelf
echo "Dune - Frank Herbert" > catalogue.txt
ln catalogue.txt catalogue-hard.txt          # hard link
ln -s catalogue.txt catalogue-soft.txt       # symbolic link
ls -li                                        # -i prints inode numbers
stat -c "%n inode=%i links=%h type=%F" catalogue*
echo "Neuromancer - William Gibson" >> catalogue-hard.txt
cat catalogue.txt
rm catalogue.txt
cat catalogue-hard.txt
cat catalogue-soft.txt
```

### Real output

```text
$ ls -li
2505321 -rw-r--r-- 2 root root 21 Oct 18 13:52 catalogue-hard.txt
2505322 lrwxrwxrwx 1 root root 13 Oct 18 13:52 catalogue-soft.txt -> catalogue.txt
2505321 -rw-r--r-- 2 root root 21 Oct 18 13:52 catalogue.txt
$ stat -c "%n inode=%i links=%h type=%F" catalogue*
catalogue-hard.txt inode=2505321 links=2 type=regular file
catalogue-soft.txt inode=2505322 links=1 type=symbolic link
catalogue.txt inode=2505321 links=2 type=regular file
$ echo "Neuromancer - William Gibson" >> catalogue-hard.txt
$ cat catalogue.txt
Dune - Frank Herbert
Neuromancer - William Gibson
$ rm catalogue.txt
$ cat catalogue-hard.txt
Dune - Frank Herbert
Neuromancer - William Gibson
$ cat catalogue-soft.txt
cat: catalogue-soft.txt: No such file or directory
$ ls -l catalogue-soft.txt
lrwxrwxrwx 1 root root 13 Oct 18 13:52 catalogue-soft.txt -> catalogue.txt
```

### What it shows

- `catalogue.txt` and `catalogue-hard.txt` share inode `2505321` and have link count 2.
- Writing through the hard link changed the "original" - there is only one copy of the data.
- After `rm catalogue.txt` the hard link still has both lines (link count dropped to 1).
- The symlink still exists (`ls -l` lists it) but it points at a path that is gone.

---

## Part 2 - `useradd` vs `adduser`

### Concept

- **`useradd`** is the low-level tool from the `passwd`/shadow package. It does only what
  you ask: no `-m` means no home directory, no `-s` means the default shell (`/bin/sh`),
  and no password is set.
- **`adduser`** is Debian/Ubuntu's friendly wrapper (Perl). It picks the next free UID,
  creates a matching group, creates the home directory, copies `/etc/skel`, sets `/bin/bash`,
  adds the user to the `users` group and (interactively) asks for a password and full name.

**Rule of thumb on Ubuntu:** `adduser` when a human is creating an account by hand;
`useradd` with explicit flags in scripts, Dockerfiles and config management, where you want
no prompts and every option visible.

### Commands

```bash
useradd -m -s /bin/bash librarian1     # explicit: home + bash
useradd archivist                      # bare: see what you do NOT get
apt-get update && apt-get install -y adduser   # not in the minimal ubuntu image
adduser --disabled-password --gecos "Library Clerk" clerk2
id librarian1; id clerk2
grep -E 'librarian1|archivist|clerk2' /etc/passwd
ls -la /home/clerk2
```

`--disabled-password --gecos ...` only make `adduser` non-interactive for the demo.

### Real output (trimmed)

```text
$ useradd -m -s /bin/bash librarian1
$ id librarian1
uid=1001(librarian1) gid=1001(librarian1) groups=1001(librarian1)
$ grep librarian1 /etc/passwd
librarian1:x:1001:1001::/home/librarian1:/bin/bash
$ useradd archivist   # no flags
$ grep archivist /etc/passwd; ls -d /home/archivist
archivist:x:1002:1002::/home/archivist:/bin/sh
ls: cannot access '/home/archivist': No such file or directory
$ adduser --disabled-password --gecos "Library Clerk" clerk2
info: Adding user `clerk2' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `clerk2' (1003) ...
info: Adding new user `clerk2' (1003) with group `clerk2 (1003)' ...
info: Creating home directory `/home/clerk2' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `clerk2' to supplemental / extra groups `users' ...
info: Adding user `clerk2' to group `users' ...
$ id clerk2
uid=1003(clerk2) gid=1003(clerk2) groups=1003(clerk2),100(users)
$ grep clerk2 /etc/passwd
clerk2:x:1003:1003:Library Clerk,,,:/home/clerk2:/bin/bash
$ ls -la /home/clerk2
-rw-r--r-- 1 clerk2 clerk2  220 Oct 18 13:52 .bash_logout
-rw-r--r-- 1 clerk2 clerk2 3771 Oct 18 13:52 .bashrc
-rw-r--r-- 1 clerk2 clerk2  807 Oct 18 13:52 .profile
```

### What it shows

- Bare `useradd archivist` registered the account in `/etc/passwd` with shell `/bin/sh`
  and a home path that **does not exist** - an account you cannot comfortably log in to.
- `useradd -m -s /bin/bash` gets you there, but only because every flag was spelled out.
- `adduser` narrated each step it took on its own, filled the GECOS field, used `/bin/bash`
  and added the extra `users` group.

---

## Part 3 - `journalctl`

### Concept

`systemd-journald` collects logs from every service, the kernel and `syslog()` callers into
a structured binary journal. `journalctl` reads it and lets you filter by *fields* instead of
grepping text files under `/var/log`.

| Command | What it filters |
|---|---|
| `journalctl -b` | current boot only (`-b -1` = previous boot) |
| `journalctl -u cron` | one systemd unit |
| `journalctl -t bookshelf` | one syslog identifier (tag) |
| `journalctl -p err` | priority `err` and more severe (`emerg`..`err`) |
| `journalctl --since "10 min ago" --until now` | time window |
| `journalctl -n 20` / `-f` | last 20 lines / follow live |
| `journalctl -o short-iso` / `-o json-pretty` | output format |
| `journalctl --disk-usage` / `--vacuum-time=7d` | journal size / cleanup |

### Running systemd in a container

A normal container has no init system, so `journalctl` has nothing to read. I started one
with systemd as PID 1:

```bash
docker run -d --name library-systemd --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw ubuntu:24.04 \
  bash -c "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y systemd cron \
           && exec /usr/lib/systemd/systemd"
docker exec library-systemd systemctl is-system-running   # wait for "running"
docker exec -it library-systemd bash
```

Inside it I restarted `cron` and wrote two log lines as a fake `bookshelf` app using `logger`:

```bash
systemctl restart cron
logger -t bookshelf -p user.warning "overdue scan found 3 late loans"
logger -t bookshelf -p user.err     "catalog sync failed: isbn index locked"
journalctl --no-pager -u cron
journalctl --no-pager -t bookshelf
journalctl --no-pager -p err -b
journalctl --no-pager --since "5 minutes ago" -n 5
journalctl --no-pager -u cron -o short-iso -n 3
journalctl --disk-usage
```

Clean up with `docker rm -f library-systemd`.

### Real output (trimmed)

```text
$ journalctl --no-pager -u cron
Oct 18 13:53:24 cc7be65d81a4 systemd[1]: Started cron.service - Regular background program processing daemon.
Oct 18 13:53:24 cc7be65d81a4 cron[3091]: (CRON) INFO (Running @reboot jobs)
Oct 18 13:53:30 cc7be65d81a4 systemd[1]: Stopping cron.service - Regular background program processing daemon...
Oct 18 13:53:30 cc7be65d81a4 systemd[1]: cron.service: Deactivated successfully.
Oct 18 13:53:30 cc7be65d81a4 systemd[1]: Stopped cron.service - Regular background program processing daemon.
Oct 18 13:53:30 cc7be65d81a4 systemd[1]: Started cron.service - Regular background program processing daemon.
Oct 18 13:53:30 cc7be65d81a4 cron[3118]: (CRON) INFO (Skipping @reboot jobs -- not system startup)
$ journalctl --no-pager -t bookshelf
Oct 18 13:53:31 cc7be65d81a4 bookshelf[3120]: overdue scan found 3 late loans
Oct 18 13:53:31 cc7be65d81a4 bookshelf[3121]: catalog sync failed: isbn index locked
$ journalctl --no-pager -p err -b
Oct 18 13:53:31 cc7be65d81a4 bookshelf[3121]: catalog sync failed: isbn index locked
$ journalctl --no-pager -u cron -o short-iso -n 3
2026-10-18T13:53:30+00:00 cc7be65d81a4 cron[3118]: (CRON) INFO (pidfile fd = 3)
2026-10-18T13:53:30+00:00 cc7be65d81a4 cron[3118]: (CRON) INFO (Skipping @reboot jobs -- not system startup)
$ journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.
```

### What it shows

- `-u cron` shows the whole life of the unit: first start at boot (with `@reboot` jobs),
  then the stop/start pair caused by my restart (note the new PID, 3091 -> 3118, and that
  `@reboot` jobs are skipped the second time).
- `-t bookshelf` isolates my app's messages from everything else.
- `-p err` returned only the `err` line; the `warning` line is less severe and was filtered out.

---

## Part 4 - Everyday command cheat sheet

**Navigate and find**

| Command | Use |
|---|---|
| `pwd`, `cd -`, `cd ~` | where am I / previous dir / home |
| `ls -lah` | long list, hidden files, human sizes |
| `find /var/log -name "*.log" -mtime -1` | files changed in the last day |
| `du -sh * \| sort -h` | what is taking space here |
| `which nginx`, `type ll` | where a command comes from |

**Files and text**

| Command | Use |
|---|---|
| `mkdir -p a/b/c`, `touch f` | nested dirs, empty file |
| `cp -a src dst`, `mv a b`, `rm -r d` | copy (keep perms), move/rename, delete |
| `cat`, `less`, `head -n 20`, `tail -f` | read / page / start / follow |
| `grep -rin "isbn" .` | case-insensitive recursive search with line numbers |
| `wc -l`, `sort`, `uniq -c`, `cut -d, -f2` | count, sort, count duplicates, pick CSV column |
| `awk -F, '{print $2}'`, `sed -i 's/old/new/g' f` | column processing, in-place replace |
| `tar -czf x.tgz dir`, `tar -xzf x.tgz` | create / extract archive |

**Permissions and users**

| Command | Use |
|---|---|
| `chmod 640 f`, `chmod u+x s.sh` | numeric / symbolic modes |
| `chown -R app:app /srv/app` | change owner and group recursively |
| `umask` | default mask for new files (0022 -> files 644, dirs 755) |
| `id`, `whoami`, `groups user` | identity and group membership |
| `sudo -i`, `su - user` | root shell / switch user |
| `passwd user`, `usermod -aG docker user` | set password / add to a group |

**Processes and system**

| Command | Use |
|---|---|
| `ps -ef`, `ps aux --sort=-%mem \| head` | list processes, top memory users |
| `top`, `htop` | live view |
| `kill -15 PID`, `kill -9 PID`, `pkill name` | graceful stop, force kill, by name |
| `jobs`, `bg`, `fg`, `nohup cmd &` | job control |
| `df -h`, `free -h`, `uptime`, `uname -a` | disk, memory, load, kernel |
| `lsblk`, `mount` | block devices and mounts |

**Services, packages, network**

| Command | Use |
|---|---|
| `systemctl status/start/stop/restart/enable --now unit` | manage services |
| `journalctl -u unit -f` | follow a service log |
| `apt update && apt install -y pkg`, `apt remove pkg` | packages |
| `ip a`, `ip route`, `ss -tulpn` | addresses, routes, listening ports |
| `curl -I url`, `ping -c 3 host` | HTTP check, reachability |

### Short practice session (real output, trimmed)

```text
$ mkdir -p library/fiction library/nonfiction library/returns
$ touch library/fiction/dune.txt library/nonfiction/sapiens.txt
$ printf "isbn,title\n9780441013593,Dune\n9780062316097,Sapiens\n" > library/index.csv
$ chmod 640 library/index.csv
$ ls -l library/index.csv
-rw-r----- 1 root root 52 Oct 18 13:53 library/index.csv
$ umask
0022
$ grep -n Dune library/index.csv
2:9780441013593,Dune
$ tar -czf library.tgz library
$ tar -tzf library.tgz | sort
library/
library/fiction/
library/fiction/dune.txt
library/index.csv
library/nonfiction/
library/nonfiction/sapiens.txt
library/returns/
$ sleep 300 & echo started sleep pid $!
started sleep pid 21
$ ps -eo pid,ppid,stat,cmd | head -n 6
    PID    PPID STAT CMD
      1       0 Ss   bash -s
     21       1 S    sleep 300
$ df -h /
Filesystem      Size  Used Avail Use% Mounted on
overlay          40G  3.8G   34G  11% /
$ uname -srm
Linux 6.8.0-117-generic aarch64
```

## Screenshots

`screenshots/` is empty for now (only `.gitkeep`). Capture these from your own terminal:

| File | What it should show |
|---|---|
| `hard-vs-soft-link.png` | `ls -li` with matching inodes, and `cat` on both links after `rm catalogue.txt` |
| `useradd-vs-adduser.png` | bare `useradd`, `useradd -m -s`, `adduser` output, and the `/etc/passwd` lines |
| `journalctl.png` | `journalctl -u cron` restart pair and `-p err` showing only the error line |
| `basic-commands.png` | the practice session above |
