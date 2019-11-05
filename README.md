Just a [MinIO](https://min.io/) container running on a Pi and sitting behind an NGINX reverse proxy. Who's got time to configure that? I mean, _I_ did, but I wish someone else had published this already. So, here you go.

"minifloppies" is simply the shortest word containing `m.*i.*n.*i.*o` and `p.*i` together in the same string. Plus, it conveniently seemed to fit this application's intended use case.

## Why use this?
While interviewing for jobs, I had to share my resume with recruiters at many different companies, as one does. I like to keep a close hold on my resume and don't care for it to float around freely. For a while, I used `cpdf` to AES-encrypt my resume and provided a password to recruiters through an out-of-band message, like SMS. That provided a pretty terrible experience for anyone that needed to read or share that document, so I decided to implement a solution that met the following requirements:
- Does not require me to host a sensitive document on third-party infrastructure. That rules out services like Firefox Send.
- Encrypts files in transit.
- Does not require entering a password.
- Allows sharing via one-time download links.

## Configure MinIO (Pi)
Install Docker ARM  using the [convenience script](https://docs.docker.com/install/linux/docker-ce/debian/#install-using-the-convenience-script).
```
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo apt purge docker-ce
sudo apt install docker-ce=18.06.3~ce~3-0~raspbian
docker --version  # Docker version 18.06.3-ce, build d7080c1
sudo systemctl enable --now docker
```

Build MinIO image.
```
cd minifloppies/minio
curl -O https://raw.githubusercontent.com/pixelchrome/minio-arm/master/Dockerfile
sudo docker build -t minio-arm .
```

Generate MinIO S3 keys.
```
./keygen.sh
```

Run MinIO container with keys generated above.
```
sudo docker run -d -p 9000:9000 \
  -e "MINIO_ACCESS_KEY=<ACCESS_KEY>" \
  -e "MINIO_SECRET_KEY=<SECRET_KEY>" \
  -v /srv/minio_data:/data \
  -v /srv/minio_config:/root/.minio \
  minio-arm server /data
```

## Configure NGINX (VPS)
Ensure that [Docker Compose](https://docs.docker.com/compose/install/#install-compose) is installed:
```
sudo curl -L "https://github.com/docker/compose/releases/download/1.24.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

Configure NGINX and start.
```
cd minifloppies/letsencrypt
echo 'URL=<URL>' > .env
sudo docker-compose up
cp site.conf /var/letsencrypt/nginx/site-confs/default
docker container exec <CONTAINER_ID> nginx -g 'pid /run/nginx.pid;' -s reload
```

## Configure reverse SSH tunnel
On VPS, create a restricted user `ssh_tunnel` who may only open SSH tunnels.
```
sudo useradd ssh_tunnel -m -d /home/ssh_tunnel -s /bin/bash
sudo passwd ssh_tunnel
```

On Pi, generate and transfer SSH keys for restricted user `ssh_tunnel`.
```
ssh-keygen -t rsa -b 4096 -o -a 100 -N '' -f ~/.ssh/ssh_tunnel
ssh-copy-id -i ~/.ssh/ssh_tunnel ssh_tunnel@<VPS>
```

On VPS, lock down restricted user `ssh_tunnel`'s login settings...
```
sudo passwd -l ssh_tunnel
sudo usermod -s /usr/sbin/nologin ssh_tunnel
```

...and SSH settings in `/etc/ssh/sshd/config`.
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
*/5 * * * * pgrep -afi 'autossh.*ssh_tunnel@<VPS>' || autossh -M 0 -o 'ServerAliveInterval 30' -o 'ServerAliveCountMax 3' -p <PORT> -f -N -R 172.17.0.1:9090:127.0.0.1:9000 -i ~/.ssh/ssh_tunnel ssh_tunnel@<VPS>
```

## Administer MinIO
Download MinIO client.
```
sudo curl -o /usr/local/bin/mc https://dl.minio.io/client/mc/release/linux-arm/mc
sudo chmod +x /usr/local/bin/mc
```

Example MinIO client usage.
```
mc config host add <HOSTNAME> <URL> <ACCESS_KEY> <SECRET_KEY>
mc mb <HOSTNAME>/share
mc cp resume.pdf <HOSTNAME>/share
mc share download --expire 96h <HOSTNAME>/share/resume.pdf
mc share list download
```
