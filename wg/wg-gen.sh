#!/bin/sh

hosts_file="wg-data.txt"
tmp_file="tmp.txt"

while read -r line; do
    hostname=$( echo "$line" | cut -d' ' -f1 )
    ip=$( echo "$line" | cut -d' ' -f2 )
    privkey=$( wg genkey )
    pubkey=$( echo $privkey | wg pubkey )
    echo "$hostname $ip $privkey $pubkey" >> $tmp_file
done < $hosts_file

while read -r host; do
    outfile="$( echo "$host" | cut -d'.' -f1 ).conf"
    ip=$( echo "$host" | cut -d' ' -f2 )
    privkey=$( echo "$host" | cut -d' ' -f3 )

    echo "[Interface]" >> $outfile
    echo "PrivateKey = $privkey" >> $outfile
    echo "Address = $ip" >> $outfile
    echo "ListenPort = 51820" >> $outfile

    while read -r peer_host; do
        if [ "$host" != "$peer_host" ]; then
            hostname=$( echo "$peer_host" | cut -d' ' -f1 )
            ip=$( echo "$peer_host" | cut -d' ' -f2 )
            pubkey=$( echo "$peer_host" | cut -d' ' -f4 )

            echo "" >> $outfile
            echo "[Peer]" >> $outfile
            echo "Endpoint = $hostname:51820" >> $outfile
            echo "PublicKey = $pubkey" >> $outfile
            echo "AllowedIPs = $ip" >> $outfile
        fi
    done < $tmp_file
done < $tmp_file

rm $tmp_file
