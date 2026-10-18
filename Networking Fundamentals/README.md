# Networking Fundamentals

**Author:** Parth Agarwal

## Goal

Learn the nine commands I reach for when "the catalogue site is down": check reachability,
look at addresses and routes, see which ports are listening, talk HTTP, download files,
resolve names, trace the path, and identify the host.

| # | Command | Question it answers |
|---|---|---|
| 1 | `ping` | Can I reach the host, and how fast? |
| 2 | `ip a` | Which interfaces and IP addresses do I have? |
| 3 | `ip route` | Where will my packets be sent? |
| 4 | `ss` | What is listening on which port, and which process owns it? |
| 5 | `curl` | Does the web service answer, and with what? |
| 6 | `wget` | Download a file to disk |
| 7 | `nslookup` / `dig` | What IP does this name resolve to, and who answered? |
| 8 | `traceroute` | Which hops does traffic pass through? |
| 9 | `hostname` | What is this machine called / what is its IP? |

## Environment

All commands were run in an `ubuntu:24.04` container on my Mac (Docker Desktop):

```bash
docker run --rm -it -h library-net ubuntu:24.04 bash
apt-get update && apt-get install -y iproute2 iputils-ping curl wget dnsutils traceroute python3
```

> **Note on the container:** Docker Desktop runs containers inside a small VM whose network
> stack NATs traffic for them. Because of that, `ping` round-trip times below are unrealistically
> low (the VM answers the ICMP itself) and `traceroute` cannot see past the first hop. For
> screenshots with realistic numbers, run `ping` and `traceroute` on the host or a real VM.

---

## 1. `ping`

```bash
ping -c 4 github.com
```

```text
PING github.com (20.207.73.82) 56(84) bytes of data.
64 bytes from 20.207.73.82: icmp_seq=1 ttl=63 time=0.421 ms
...
--- github.com ping statistics ---
4 packets transmitted, 4 received, 0% packet loss, time 3081ms
rtt min/avg/max/mdev = 0.247/0.367/0.468/0.084 ms
```

Read: the name is resolved first, then one ICMP echo per line. The summary gives packet loss
and min/avg/max/mdev latency. `-c` limits the count (Linux pings forever otherwise).
A failed ping is not proof the host is down - many firewalls drop ICMP.

## 2. `ip a`

```bash
ip -br a          # brief, one line per interface
ip a show eth0    # full detail for one interface
```

```text
lo               UNKNOWN        127.0.0.1/8 ::1/128
eth0@if82        UP             172.17.0.3/16
$ ip a show eth0
2: eth0@if82: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default
    link/ether 6e:74:10:27:39:7b brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.3/16 brd 172.17.255.255 scope global eth0
```

Read: `lo` is loopback; `eth0` is the container's end of a veth pair on the default Docker
bridge, address `172.17.0.3` in a `/16` network (65,534 usable hosts). `UP,LOWER_UP` means the
link is administratively up and has carrier. `link/ether` is the MAC address. `ip` replaces
the deprecated `ifconfig`.

## 3. `ip route`

```bash
ip route
ip route get 1.1.1.1
```

```text
default via 172.17.0.1 dev eth0
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.3
$ ip route get 1.1.1.1
1.1.1.1 via 172.17.0.1 dev eth0 src 172.17.0.3 uid 0
```

Read: anything in `172.17.0.0/16` is delivered directly on `eth0`; everything else goes to the
default gateway `172.17.0.1` (the Docker bridge). `ip route get` shows the exact decision the
kernel makes for one destination - handy when a box has several interfaces or VPN routes.

## 4. `ss`

To have something listening, I served a one-line `reader-web` page with Python:

```bash
mkdir -p /srv/reader-web && echo '<h1>reader-web: 42 books on loan</h1>' > /srv/reader-web/index.html
cd /srv/reader-web && python3 -m http.server 8080 &
ss -tlnp
ss -s
```

```text
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      5            0.0.0.0:8080      0.0.0.0:*    users:(("python3",pid=2924,fd=3))
```

Read: flags are `-t` TCP, `-l` listening, `-n` numeric (no name lookups), `-p` owning process
(add `-u` for UDP). `0.0.0.0:8080` means all interfaces; `127.0.0.1:8080` would be local-only,
a classic reason a service "works on the box but not from outside". `ss -s` prints totals per
protocol. `ss` replaces `netstat`.

## 5. `curl`

```bash
curl -s http://localhost:8080/                 # body
curl -sI http://localhost:8080/                # headers only (HEAD)
curl -sI https://github.com
curl -s -o /dev/null -w 'code=%{http_code} dns=%{time_namelookup}s connect=%{time_connect}s total=%{time_total}s\n' https://example.com/
```

```text
<h1>reader-web: 42 books on loan</h1>
$ curl -sI http://localhost:8080/
HTTP/1.0 200 OK
Server: SimpleHTTP/0.6 Python/3.12.3
Content-type: text/html
Content-Length: 38
$ curl -sI https://github.com            (trimmed)
HTTP/2 200
content-type: text/html; charset=utf-8
strict-transport-security: max-age=31536000; includeSubdomains; preload
x-frame-options: deny
server: github.com
$ curl -s -o /dev/null -w '...' https://example.com/
code=200 dns=0.094761s connect=0.207354s total=0.600873s
```

Read: the status line is the first thing to check. `-w` with timing variables splits a slow
request into DNS, TCP connect and total time - very useful for "the site is slow" tickets.
Other everyday flags: `-v` (show request/response and TLS), `-L` (follow redirects),
`-X POST -H 'Content-Type: application/json' -d '{...}'` (call an API).

## 6. `wget`

```bash
wget https://example.com/
wget -q -O page.html https://example.com/
ls -l index.html page.html
```

```text
Resolving example.com (example.com)... 172.66.147.243, 104.20.23.154
Connecting to example.com (example.com)|172.66.147.243|:443... connected.
HTTP request sent, awaiting response... 200 OK
Saving to: 'index.html'
2026-10-18 13:54:27 (132 MB/s) - 'index.html' saved [577]
$ ls -l index.html page.html
-rw-r--r-- 1 root root 577 Oct 13 20:08 index.html
-rw-r--r-- 1 root root 577 Oct 13 20:08 page.html
```

Read: `wget` narrates resolve -> connect -> response -> save. It writes to a file by default
(named after the URL), where `curl` writes to stdout. `-O` sets the name, `-q` silences it,
`-c` resumes a partial download, `-r` mirrors recursively. The file date comes from the
server's `Last-Modified` header, not the download time.

## 7. `nslookup` and `dig`

```bash
nslookup github.com
dig +short github.com
dig +noall +answer openlibrary.org
cat /etc/resolv.conf
```

```text
Server:		192.168.5.1
Address:	192.168.5.1#53

Non-authoritative answer:
Name:	github.com
Address: 20.207.73.82
$ dig +short github.com
20.207.73.82
$ dig +noall +answer openlibrary.org
openlibrary.org.	0	IN	A	207.241.234.205
$ cat /etc/resolv.conf   (trimmed)
# Generated by Docker Engine.
nameserver 192.168.5.1
```

Read: `Server` is the resolver that answered - here Docker's VM resolver from
`/etc/resolv.conf`. "Non-authoritative" means it came from a cache, not the domain's own name
server. `dig +short` gives just the answer (good for scripts); `+noall +answer` adds the record
type and TTL. If `ping 1.1.1.1` works but `ping github.com` does not, suspect DNS.

## 8. `traceroute`

```bash
traceroute -m 12 -w 2 -q 1 github.com
```

```text
traceroute to github.com (20.207.73.82), 12 hops max, 60 byte packets
 1  172.17.0.1 (172.17.0.1)  0.392 ms
 2  *
 3  *
 ...
12  *
```

Read: traceroute sends probes with TTL 1, 2, 3, ... so each router on the way returns
"time exceeded" and reveals itself. `*` means no reply within `-w` seconds. Here only the
Docker bridge (hop 1) answered, because the desktop VM's NAT does not pass those replies
back - see the note at the top. On a normal Linux host or VM you see your home router,
the ISP hops and finally the destination network. `-m` caps hops, `-q 1` sends one probe per hop.

## 9. `hostname`

```bash
hostname
hostname -I
hostname -f
```

```text
library-net
172.17.0.3
library-net
```

Read: the short name (set with `docker run -h`), all IPv4 addresses on one line, and the
fully-qualified name (no domain configured, so it is the same). On a real server,
`hostnamectl` shows and sets it permanently.

## Troubleshooting order I use

1. `ip a` / `ip route` - do I have an address and a default route?
2. `ping <gateway>` then `ping 1.1.1.1` - local network, then internet.
3. `dig <name>` - is DNS working?
4. `ss -tlnp` on the server - is the service listening, and on which address?
5. `curl -v` - what does the application actually return?
6. `traceroute` - where along the path does it break or slow down?

## Screenshots

`screenshots/` contains only `.gitkeep`. Capture one per command:
`ping.png`, `ip-a.png`, `ip-route.png`, `ss.png`, `curl.png`, `wget.png`, `nslookup-dig.png`,
`traceroute.png` (preferably from the host or a VM, so real hops are visible), `hostname.png`.
