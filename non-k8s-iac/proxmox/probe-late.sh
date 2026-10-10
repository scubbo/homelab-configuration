#!/bin/bash
set -euo pipefail
install -d -o scubbo -g scubbo -m 700 /home/scubbo/.ssh
install -o scubbo -g scubbo -m 600 /root/probe-authorized_keys /home/scubbo/.ssh/authorized_keys
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' > /etc/ssh/sshd_config.d/20-probe-key-auth.conf
printf 'GRUB_CMDLINE_LINUX="console=tty0 console=ttyS0,115200n8 systemd.ssh_auto=no"\nGRUB_TERMINAL="console serial"\nGRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"\n' > /etc/default/grub.d/serial.cfg
update-grub
systemctl enable ssh.service qemu-guest-agent.service serial-getty@ttyS0.service
systemctl disable iperf3.service
printf 'Debian probe installation completed\n' > /root/probe-install.complete
