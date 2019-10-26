Just a [MinIO](https://min.io/) container running on a Pi and sitting behind an NGINX reverse proxy. But who's got time to configure that? I mean, _I_ did, but I wish someone else had published this already. So here you go.

"minifloppies" is simply the shortest word containing `m.*i.*n.*i.*o` and `p.*i` together in the same string. Plus, it conveniently seemed to fit this application's intended use case.

# Install and configure MinIO
Install Docker ARM on Pi using [convenience script](https://docs.docker.com/install/linux/docker-ce/debian/#install-using-the-convenience-script).
```
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt purge docker-ce
sudo apt install docker-ce=18.06.3~ce~3-0~raspbian
docker --version  # Docker version 18.06.3-ce, build d7080c1
sudo systemctl enable --now docker
```

Install MinIO server.
```
curl -O https://raw.githubusercontent.com/pixelchrome/minio-arm/master/Dockerfile
sudo docker build -t minio-arm .
```

Make directories for MinIO container.
```
sudo mkdir -p /srv/minio_data /srv/minio_config
```

Generate keys.
```
#!/bin/sh
echo -n 'ACCESS KEY: '
base64 /dev/urandom | tr -d '/+' | head -c 20 | tr '[:lower:]' '[:upper:]'
echo
echo -n 'SECRET KEY: '
base64 /dev/urandom | tr -d '/+' | head -c 40
echo
```

Run MinIO container with unique keys.
```
sudo docker run -d -p 9000:9000 \
  -e "MINIO_ACCESS_KEY=[ACCESS_KEY]" \
  -e "MINIO_SECRET_KEY=[SECRET_KEY]" \
  -v /srv/minio_data:/data \
  -v /srv/minio_config:/root/.minio \
  minio-arm server /data
```

Download MinIO client.
```
sudo curl -o /usr/local/bin/mc https://dl.minio.io/client/mc/release/linux-arm/mc
sudo chmod +x /usr/local/bin/mc
```

Example MinIO client usage.
```
mc config host add [HOSTNAME] [URL] [ACCESS_KEY] [SECRET_KEY]
mc mb [HOSTNAME]/resume
mc cp resume.pdf [HOSTNAME]/resume
mc share download --expire 96h [HOSTNAME]/resume/resume.pdf
mc share list download
```

## Connect MinIO to NGINX
Generate keys for `ssh_tunnel`, a restricted user on a VPS who may only open SSH tunnels.
```
ssh-keygen -t rsa -b 4096 -o -a 100 -N '' -f "$HOME/.ssh/[SSH_TUNNEL_KEY]"
```

On VPS, create the restricted `ssh_tunnel` user.
```
sudo useradd ssh_tunnel -m -d /home/ssh_tunnel -s /bin/bash
sudo passwd ssh_tunnel
sudo passwd -l ssh_tunnel
sudo su ssh_tunnel
```

Manually copy over SSH public key and lock down `ssh_tunnel` user.
```
cd
umask 0077
mkdir -p .ssh
vim .ssh/authorized_keys
chmod 700 .ssh
chmod 600 .ssh/authorized_keys
chmod g-w,o-w .
exit
sudo usermod -s /usr/sbin/nologin ssh_tunnel
```

In VPS's `/etc/ssh/sshd_config`, lock down `ssh_tunnel`'s SSH settings.
```
Match User ssh_tunnel
  AllowTcpForwarding yes
  X11Forwarding no
  PermitTunnel no
  GatewayPorts clientspecified
  AllowAgentForwarding no
```

On Pi, start persistent SSH tunnel to VPS via `cron` + `autossh`.
```
*/5 * * * * pgrep -afi 'autossh.*ssh_tunnel@[VPS]' || autossh -M 0 -o 'ServerAliveInterval 30' -o 'ServerAliveCountMax 3' -p [PORT] -f -N -R [DOCKER_IP]:9000:127.0.0.1:9000 -i ~/.ssh/[SSH_TUNNEL_KEY] ssh_tunnel@[VPS]
```

On VPS, enable firewall.
```
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
firewall-cmd --permanent --new-zone=docker
firewall-cmd --reload
firewall-cmd --permanent --zone=docker --add-interface=docker0
firewall-cmd --permanent --zone=docker --add-port=9000/tcp
firewall-cmd --reload
```
