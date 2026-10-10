#!/bin/bash
set -euo pipefail
install -d -o scubbo -g scubbo -m 700 /home/scubbo/.ssh
install -o scubbo -g scubbo -m 600 /root/guest-authorized_keys /home/scubbo/.ssh/authorized_keys
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/20-guest-key-auth.conf
printf 'GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8 systemd.ssh_auto=no"\nGRUB_TERMINAL="console serial"\nGRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"\n' > /etc/default/grub.d/serial.cfg
update-grub
systemctl enable ssh.service qemu-guest-agent.service serial-getty@ttyS0.service iscsid.service
install -d -m 755 /etc/modules-load.d /etc/sysctl.d
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k3s.conf
printf 'net.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-iptables = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n' > /etc/sysctl.d/90-k3s.conf
printf 'Debian Kubernetes guest installation completed\n' > /root/guest-install.complete
