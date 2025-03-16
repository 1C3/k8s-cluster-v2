## Part 1: Node Setup

### os install

- before booting a live image on the node:
  - enter bios
  - put secure boot into setup mode
  - reset TPM

- boot live usb, start a root shell

- format disk with 1GB EFI partition and fill the rest of the space with encrypted root
```
DISK='/dev/sda'
ESP='/dev/sda1'
ROOT='/dev/sda2'

blkdiscard -f $DISK
parted $DISK --script \
mklabel gpt \
mkpart primary 0% 1GiB \
set 1 esp on \
mkpart primary 1GiB 100%
```

- create encrypted container for root partition, format partitions, then mount them
```
cryptsetup luksFormat --cipher aes-xts-plain64 --key-size 512 --hash sha512 --pbkdf argon2id --pbkdf-parallel 4 --iter-time 1000 $ROOT
cryptsetup luksOpen --allow-discards --perf-no_write_workqueue --perf-no_read_workqueue --persistent $ROOT root

mkfs.vfat -F32 -n ESP $ESP
mkfs.ext4 -L ROOT -O fast_commit /dev/mapper/root

mkdir -p /mnt/gentoo
mount /dev/mapper/root /mnt/gentoo
mkdir -p /mnt/gentoo/efi
mount $ESP /mnt/gentoo/efi
```

- get stage3, check checksums match, extract
```
current_stage3=$( curl -s https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-nomultilib-systemd/latest-stage3-amd64-nomultilib-systemd.txt | grep -oP '^stage3\S+' )
cd /mnt/gentoo

wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-nomultilib-systemd/${current_stage3}"
wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-nomultilib-systemd/${current_stage3}.DIGESTS"
if [[ $(sha512sum stage3*.tar.xz) = $(sed -n '/SHA512 HASH/{ n; /.*.tar.xz$/p }' stage3*.DIGESTS) ]]; then echo 'CHECKSUMS MATCH'; fi
tar xpvf stage3*.tar.xz --xattrs-include='*.*' --numeric-owner

git clone https://github.com/1C3/k8s-cluster-v2.git
```

- chroot into the new system:
```
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run
chroot /mnt/gentoo /bin/bash

source /etc/profile
export PS1="(chroot) ${PS1}"
```

- clone this repo, copy configuration files, emerge packages
```
cd k8s-cluster-v2
cp -f etc/{make.conf,package.use} /etc/portage/
chmod 644 /etc/portage/{make.conf,package.use}

emerge-webrsync
emerge -quDN @world
emerge -q app-admin/eclean-kernel \
app-crypt/sbctl \
app-crypt/tpm2-tools \
app-shells/bash-completion \
dev-vcs/git \
net-analyzer/traceroute \
net-misc/telnet-bsd \
net-vpn/wireguard-tools \
net-wireless/iwd \
sys-boot/efibootmgr \
sys-firmware/intel-microcode \
sys-kernel/gentoo-sources \
sys-kernel/installkernel \
sys-kernel/linux-firmware \
sys-process/htop
```

- set root password
```
passwd
```

### kernel install

- prepare dracut.conf and fstab
```
ESP='/dev/sda1'
ROOT='/dev/sda2'
LUKS_ID=$( blkid | grep $ROOT | grep -oP '(?<= UUID=")[^"]+' )
ROOT_ID=$( blkid | grep /dev/mapper/root | grep -oP '(?<= UUID=")[^"]+' )
ESP_ID=$( blkid | grep $ESP | grep -oP '(?<= UUID=")[^"]+' )

cat <<EOF > /etc/dracut.conf
add_dracutmodules+=" systemd-cryptsetup tpm2-tss "
kernel_cmdline="root=UUID=$ROOT_ID rd.luks.uuid=$LUKS_ID rd.luks.options=$LUKS_ID=tpm2-device=auto rd.luks.options=tpm2-measure-pcr=yes fsck.mode=force fsck.repair=yes"
early_microcode="yes"
compress="zstd"
EOF

cat <<EOF > /etc/fstab
UUID=$ROOT_ID /     ext4  defaults,noatime,discard  0 1
UUID=$ESP_ID  /efi  vfat  defaults,noatime          0 2
EOF
```

- use sbctl to generate and enroll uefi signing keys:
```
sbctl status
sbctl create-keys
sbctl enroll-keys --yes-this-might-brick-my-machine
sbctl status
```

- build and install uki
```
export KCFLAGS=' -march=gracemont'
export KCPPFLAGS=' -march=gracemont'

cp etc/kconfig /usr/src/linux/
cd /usr/src/linux
make olddefconfig
make -j4
make modules_install
make install
```

- install and run efi boot entry updater script, reboot
```
cp bin/uki-boot-update /usr/local/bin/
chmod 544 /usr/local/bin/uki-boot-update
uki-boot-update
reboot
```

### finishing os setup

- use recovery password to unlock root partition for the first boot, since the tpm doesn't hold the secret yet

- configure ssh, get node local network ip
```
sed -i 's/#\?PermitRootLogin .\+/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl enable --now sshd
ip -4 r | grep default | grep -oE 'src [0-9.]+' | grep -oE '[0-9.]+'
```

- connect to the node via ssh
  - `ssh-copy-id -i ~/.ssh/keyname root@<IP>` from a host that holds the private key, then install ssh key
```
sed -i 's/#\?PermitRootLogin .\+/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
```

- configure systemd
```
HOSTNAME=hbox1
systemd-machine-id-setup
hostnamectl set-hostname $HOSTNAME
ln -sf ../usr/share/zoneinfo/Europe/Rome /etc/localtime
systemctl enable --now systemd-timesyncd
```

- setup tpm2 key for auto unlocking of root partition:
```
ROOT='/dev/sda2'
TPM='/dev/tpmrm0' # systemd-cryptenroll --tpm2-device=list
systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=$TPM --tpm2-pcrs=0+1+2+7+15:sha256=0000000000000000000000000000000000000000000000000000000000000000 $ROOT
```

- update dracut.conf to avoid unneeded modules, and to avoid dropping to root shell in case of boot errors
```
sed '/kernel_cmdline/s/"$/ panic=0"/' /etc/dracut.conf > /etc/dracut.conf.tmp
cp /etc/dracut.conf.tmp /etc/dracut.conf
echo 'hostonly="yes"' >> /etc/dracut.conf
cd /usr/src/linux
make install
```

- remove stage3 and reboot
```
rm /stage3*
reboot
```

### networking

- copy networkd configuration files
```
cp systemd/*.network /etc/systemd/network/
chmod 644 /etc/systemd/network/*.network
systemctl enable --now systemd-networkd
```

- if wireless is needed
```
SSID='<SSID>'
PASSPHRASE='<PASSPHRASE>'

cat <<EOF > "/var/lib/iwd/${SSID}.psk"
[Security]
Passphrase=$PASSPHRASE
EOF

systemcl enable --now iwd
```

- setup resolved
```
cp systemd/resolved.conf /etc/systemd/
chmod 644 /etc/systemd/resolved.conf
ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemcl enable --now systemd-resolved
```

- install cpu monitor and power limits config script
```
cp bin/cpu-* /usr/local/bin/
chmod 544 /usr/local/bin/cpu-*
```

- install cpu power limits configurations service
```
cp systemd/cpu-pl-set.service /etc/systemd/system/
chmod 444 /etc/systemd/system/cpu-pl-set.service

systemctl daemon-reload
systemctl enable --now cpu-pl-set.service
```

## Part 2: VPN Connectivity

### dns update

- write cloudflare dns api token in a secure location
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

### wireguard connection

- set iptables rules using a systemd service:
```
cp bin/iptables-rules-* /usr/local/bin/
chmod 544 /usr/local/bin/iptables-rules-*

cp systemd/iptables-rules.service /etc/systemd/system/
chmod 444 /etc/systemd/system/iptables-rules.service

eselect iptables set xtables-nft-multi
systemctl daemon-reload
systemctl enable --now iptables-rules.service
```

- generate wireguard configs:
```
cd wg
sh wg-gen.sh
```

- copy wireguard configs on each host in **/etc/wireguard**, then `systemctl enable wg-quick@<CONFIG NAME>`
