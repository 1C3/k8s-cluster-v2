- write api token in a secure location

```
mkdir -p /etc/auth/
echo $TOKEN > /etc/auth/cloudflare_api_token
chmod 400 /etc/auth/cloudflare_api_token
```

- create dns updater script, and make it executable

```
cp bin/dns-update /usr/local/bin/
chmod 500 /usr/local/bin/dns-update
```

- setup systemd timer running every minute

```
cp systemd/dns-update.* /etc/systemd/system/
chmod 500 /usr/local/bin/dns-update.*

systemctl daemon-reload
systemctl enable --now dns-update.timer
```

- set iptables rules using a systemd service:
```
cp bin/iptables-rules-* /usr/local/bin/
chmod 500 /usr/local/bin/iptables-rules-*

cp systemd/iptables-rules.service /etc/systemd/system/
chmod 500 /usr/local/bin/iptables-rules.service

systemctl daemon-reload
systemctl enable --now iptables-rules.service
```