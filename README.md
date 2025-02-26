- write api token in a secure location

```
mkdir -p /etc/auth/
echo $TOKEN > /etc/auth/cloudflare_api_token
chmod 400 /etc/auth/cloudflare_api_token
```

- create dns updater script, and make it executable

```
cp bin/dns-update /usr/local/bin/
chmod 544 /usr/local/bin/dns-update
```

- setup systemd timer running every minute

```
cp systemd/dns-update.* /etc/systemd/system/
chmod 444 /etc/systemd/system/dns-update.*

systemctl daemon-reload
systemctl enable --now dns-update.timer
```

- set iptables rules using a systemd service:
```
cp bin/iptables-rules-* /usr/local/bin/
chmod 544 /usr/local/bin/iptables-rules-*

cp systemd/iptables-rules.service /etc/systemd/system/
chmod 444 /etc/systemd/system/iptables-rules.service

systemctl daemon-reload
systemctl enable --now iptables-rules.service
```

- generate wireguard configs:
```
cd wg
sh wg-gen.sh
```

- copy wireguard configs on each host in **/etc/wireguard**, then `systemctl enable wg-quick@<CONFIG NAME>`
