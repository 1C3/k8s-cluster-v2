#!/bin/sh

hosts='hbox1.ic3.systems 10.90.0.1
hbox2.ic3.systems 10.90.0.2
hbox3.ic3.systems 10.90.0.3
'

tmp_file="tmp.txt"

printf "%s" "$hosts" | while IFS='' read line;do
    hostname=$( echo "$line" | cut -d ' ' -f 1 )
    ip=$( echo "$line" | cut -d ' ' -f 2 )
    privkey=$( wg genkey )
    pubkey=$( echo $privkey | wg pubkey )
    echo "$hostname $ip $privkey $pubkey" >> $tmp_file
done

cat $tmp_file | while read host; do
    outfile="$( echo "$host" | cut -d '.' -f 1 ).conf"
    ip=$( echo "$host" | cut -d ' ' -f 2 )
    privkey=$( echo "$host" | cut -d ' ' -f 3 )

    > $outfile
    echo "[Interface]" >> $outfile
    echo "PrivateKey = $privkey" >> $outfile
    echo "Address = $ip" >> $outfile
    echo "ListenPort = 51820" >> $outfile

    cat $tmp_file | while read peer_host; do
        if [ "$host" != "$peer_host" ]; then
            hostname=$( echo "$peer_host" | cut -d ' ' -f 1 )
            ip=$( echo "$peer_host" | cut -d ' ' -f 2 )
            pubkey=$( echo "$peer_host" | cut -d ' ' -f 4 )

            echo "" >> $outfile
            echo "[Peer]" >> $outfile
            echo "Endpoint = $hostname:51820" >> $outfile
            echo "PublicKey = $pubkey" >> $outfile
            echo "AllowedIPs = $ip" >> $outfile
        fi
    done
done

rm $tmp_file
