#!/bin/bash
# cloud-init runs this once, as root, on first boot (on real AWS).
dnf install -y nginx
echo "<h1>reader-web on $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
systemctl enable --now nginx
