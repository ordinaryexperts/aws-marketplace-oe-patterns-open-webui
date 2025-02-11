#!/bin/bash

# aws cloudwatch
sed -i 's/ASG_APP_LOG_GROUP_PLACEHOLDER/${AsgAppLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
sed -i 's/ASG_SYSTEM_LOG_GROUP_PLACEHOLDER/${AsgSystemLogGroup}/g' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

mkdir -p /opt/oe/patterns


# nginx
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/ssl/private/nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj '/CN=localhost'

cat <<EOF > /etc/nginx/sites-available/openwebui
server {
    listen 443 ssl http2;
    server_name ${Hostname};

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!MEDIUM:!LOW:!aNULL:!NULL:!SHA;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    ssl_certificate     /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    location /elb-check {
        access_log off;
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    # Proxy to 127.0.0.1:8080
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

rm /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/openwebui /etc/nginx/sites-enabled/openwebui
service nginx stop
service nginx enable
service nginx start

mkdir /data
chown app:app /data
cat <<EOF > /home/app/start-openwebui.sh
#!/bin/bash
source /home/app/.bashrc
export DATA_DIR=/data
export WEBUI_SECRET_KEY=assdfsdlfksjdfkldkjfsldkfjslfkajdsflskf
/home/app/.pyenv/shims/open-webui serve
EOF
chown app:app /home/app/start-openwebui.sh
chmod 700 /home/app/start-openwebui.sh

cat <<EOF > /etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI
After=network.target

[Service]
Type=simple
ExecStart=/home/app/start-openwebui.sh
KillSignal=SIGTERM
KillMode=mixed
Restart=always
RestartSec=3
StandardError=syslog
User=app

[Install]
WantedBy=multi-user.target
EOF

systemctl enable open-webui.service
systemctl start open-webui.service
echo hi
success=$?

# give open-webui 2 minutes to come up
sleep 120

# preload deepseek-r1:1.5b
time curl http://localhost:11434/api/generate -d '{"model": "deepseek-r1:1.5b", "keep_alive": -1}'

HOST_ENTRY="${Hostname}"
# this is needed if service isn't publicly available
if ! grep -q "127.0.0.1.*$HOST_ENTRY" /etc/hosts; then
    sed -i "/127.0.0.1/s/$/ $HOST_ENTRY/" /etc/hosts
fi

URL="https://${Hostname}"
TIMEOUT=15
MAX_RETRIES=20

# Only attempt wget if the service start was successful
if [ $success -eq 0 ]; then
    for ((i=1; i<=MAX_RETRIES; i++)); do
        wget --no-check-certificate --timeout=$TIMEOUT --tries=1 --spider "$URL" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Successfully reached $URL"
            success=0  # Indicate success
            break
        fi
        echo "Attempt $i/$MAX_RETRIES to reach $URL failed...retrying in $TIMEOUT seconds..."
        sleep $TIMEOUT
    done

    if [ $i -gt $MAX_RETRIES ]; then
        echo "Failed to reach $URL after $MAX_RETRIES attempts."
        success=1  # Indicate failure
    fi
else
    echo "Service failed to start. Skipping URL checks."
    success=1  # Indicate failure
fi

cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
