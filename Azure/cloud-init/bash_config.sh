#!/usr/bin/env bash

LOGFILE="/var/log/user-creation.log"
exec >>"$LOGFILE" 2>&1

printf "/n Add Color to PS1 Prompt /n"
echo "export PS1='\[\033[01;31m\]\u\[\033[01;33m\]@\[\033[01;36m\]\h\[\033[01;33m\]:\w \[\033[01;35m\]\$ \[\033[00m\]\n'" |tee -a /root/.bashrc
echo "export PS1='\[\033[01;32m\]\u\[\033[01;33m\]@\[\033[01;36m\]\h\[\033[01;33m\]:\w \[\033[01;35m\]\$ \[\033[00m\]\n'" |tee -a /home/odbadmin/.bashrc
echo "export PS1='\[\033[01;34m\]\u\[\033[01;33m\]@\[\033[01;36m\]\h\[\033[01;33m\]:\w \[\033[01;35m\]\$ \[\033[00m\]\n'" |tee -a /etc/skel/.bashrc

printf "\n Increase History Size \n"
echo "HISTSIZE=10000" |tee -a /root/.bashrc
echo "HISTSIZE=10000" |tee -a /home/odbadmin/.bashrc
echo "HISTSIZE=10000" |tee -a /etc/skel/.bashrc
echo "HISTFILESIZE=10000" |tee -a /root/.bashrc
echo "HISTFILESIZE=10000" |tee -a /home/odbadmin/.bashrc
echo "HISTFILESIZE=10000" |tee -a /etc/skel/.bashrc

printf "\n create groups dmngrp,irisusr,epicuser,epicsys,iscagent \n"
groupadd --gid 723 dmngrp
groupadd --gid 724 irisusr
groupadd --gid 725 epicuser
groupadd --gid 726 epicsys
groupadd --gid 727 iscagent

printf "\n create users epicadm, epicdmn, iscagent, epicsupt \n"
useradd -u 9999 -G wheel epicadmin
useradd -u 1002 -G dmngrp,irisusr,epicuser,epicsys -g epicsys epicadm
useradd -u 1003 -G dmngrp,epicuser -g epicuser epicdmn
useradd -u 1004 -G iscagent -g iscagent iscagent
useradd -u 1005 -G epicuser -g epicuser epicsupt

printf "\n Configure passwordless sudo for odbadmin \n"
echo "odbadmin ALL=(ALL) NOPASSWD:ALL" |tee -a /etc/sudoers.d/odbadmin
        
printf "\n chmod 0440 /etc/sudoers.d/odbadmin \n"
chmod 0440 /etc/sudoers.d/odbadmin
        
# Configure SSH to allow key authentication
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        
# Restart SSH service
systemctl restart sshd

# Verify lvm2 is installed
which pvcreate || dnf install -y lvm2

# Wait for volume to be attached and visible
timeout 90 sh -c 'until [ -e /dev/nvme0n2 ]; do sleep 2; done'

printf "\n Setup Instance Disk layout \n"
lsblk
printf "\n\n"
vgcreate -s 4M instvg /dev/nvme0n2
lvcreate -n epiclv -L 20G instvg
lvcreate -n epictmplv -L 50G instvg
lvcreate -n poclv -L 130G instvg
mkfs.xfs -K /dev/instvg/epiclv
mkfs.xfs -K /dev/instvg/epictmplv
mkfs.xfs -K /dev/instvg/poclv
echo "/dev/mapper/instvg-epiclv /epic   xfs defaults,nofail 0 0" >> /etc/fstab
echo "/dev/mapper/instvg-epictmplv /epic/tmp   xfs defaults,nofail 0 0" >> /etc/fstab
echo "/dev/mapper/instvg-poclv /epic/poc   xfs defaults,nofail 0 0" >> /etc/fstab
mkdir /epic
mount /dev/mapper/instvg-epiclv /epic
mkdir -p /epic/tmp
mkdir -p /epic/poc
systemctl daemon-reload
mount -a
df -h
chmod -R 2755 /epic
chown -R epicadm:epicsys /epic

printf "\n Setup Journal Disk layout \n"
timeout 90 sh -c 'until [ -e /dev/nvme0n3 ]; do sleep 2; done'
vgcreate -s 4M jrnvg /dev/nvme0n3
lvcreate -n jrnlv -L 125G jrnvg
lvcreate -n epicfileslv -L 40G jrnvg
mkfs.xfs -K /dev/jrnvg/jrnlv
mkfs.xfs -K /dev/jrnvg/epicfileslv
echo "/dev/mapper/jrnvg-jrnlv /epic/jrn xfs defaults,nofail 0 0" >> /etc/fstab
echo "/dev/mapper/jrnvg-epicfileslv /epicfiles/nonprdfiles xfs defaults,nofail 0 0" >> /etc/fstab
mkdir -p /epic/jrn
mkdir -p /epicfiles/nonprdfiles
systemctl daemon-reload
mount -a
df -h
printf "\n\n"
chmod 2755 /epic/jrn
chown epicadm:epicsys /epic/jrn
chmod 2755 /epicfiles/nonprdfiles
chown epicadm:epicsys /epicfiles/nonprdfiles
ln -s /epicfiles/nonprdfiles /epic/nonprdfiles
ls -lah /epic

printf "\n Setup Striped Data Disk layout \n"
# set -ge to number of luns 15 for PRD with all disks currently
timeout 99 sh -c 'until [ $(ls /dev/nvme0n* 2>/dev/null |grep -v p| wc -l) -ge 7 ]; do sleep 2; done'
# set [] to nubmer of disks in stripe [4-15] for 12 disks
vgcreate -s 4M prdvg /dev/nvme0n[4-7]
vgs -v
# set -i to nubmer of disks in stripe
lvcreate -n prd01lv -L 300G -i 4 -I 4M prdvg
lvs -o lv_name,vg_name,lv_size,stripes,stripesize,devices
mkfs.xfs -K /dev/prdvg/prd01lv
echo "/dev/mapper/prdvg-prd01lv /epic/prd01 xfs defaults,nofail 0 0" >> /etc/fstab
mkdir -p /epic/prd01
systemctl daemon-reload
mount -a
df -h
printf "\n\n"
chmod 755 /epic/prd01
chown epicadm:epicsys /epic/prd01

printf "\n Update VM \n"       
dnf update -y