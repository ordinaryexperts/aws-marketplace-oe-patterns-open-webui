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
service nginx start

cat <<'EOF' > /root/start-vllm.sh
#!/bin/bash

# Ensure Conda is properly initialized for this session
eval "$(conda shell.bash hook)"

# Activate the open-webui environment
conda activate open-webui || { echo "Failed to activate Conda environment 'open-webui'"; exit 1; }

# Ensure vllm is installed
if ! command -v vllm &> /dev/null; then
    echo "vllm not found. Make sure it is installed in the 'open-webui' environment."
    exit 1
fi

# Start vllm
vllm serve ${ModelName}
EOF
chmod 700 /root/start-vllm.sh

cat <<'EOF' > /etc/systemd/system/vllm.service
[Unit]
Description=vLLM
After=network.target

[Service]
Type=simple
ExecStart=/root/start-vllm.sh
KillSignal=SIGTERM
KillMode=mixed
Restart=always
RestartSec=3
StandardOutput=append:/var/log/vllm.log
StandardError=append:/var/log/vllm.log
Environment="PATH=/root/miniconda3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF
systemctl enable vllm.service
systemctl start vllm.service

cat <<EOF > /etc/logrotate.d/vllm
/var/log/vllm.log {
    daily
    rotate 7
    copytruncate
    compress
    missingok
    notifempty
}
EOF

cat <<'EOF' > /root/start-open-webui.sh
#!/bin/bash

# Ensure Conda is properly initialized for this session
eval "$(conda shell.bash hook)"

# Activate the open-webui environment
conda activate open-webui || { echo "Failed to activate Conda environment 'open-webui'"; exit 1; }

# Ensure open-webui is installed
if ! command -v open-webui &> /dev/null; then
    echo "open-webui not found. Make sure it is installed in the 'open-webui' environment."
    exit 1
fi

# Set up environment variables
export DATA_DIR=/data
export WEBUI_SECRET_KEY=assdfsdlfksjdfkldkjfsldkfjslfkajdsflskf
export OPENAI_API_BASE_URL=http://127.0.0.1:8000/v1

# Start Open WebUI
open-webui serve
EOF
chmod 700 /root/start-open-webui.sh

cat <<'EOF' > /etc/systemd/system/open-webui.service
[Unit]
Description=Open WebUI
After=network.target

[Service]
Type=simple
ExecStart=/root/start-open-webui.sh
KillSignal=SIGTERM
KillMode=mixed
Restart=always
RestartSec=3
StandardOutput=append:/var/log/open-webui.log
StandardError=append:/var/log/open-webui.log
Environment="PATH=/root/miniconda3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/logrotate.d/open-webui
/var/log/open-webui.log {
    daily
    rotate 7
    copytruncate
    compress
    missingok
    notifempty
}
EOF

systemctl enable open-webui.service
systemctl start open-webui.service
success=$?

HOST_ENTRY="${Hostname}"
# this is needed if service isn't publicly available
if ! grep -q "127.0.0.1.*$HOST_ENTRY" /etc/hosts; then
    sed -i "/127.0.0.1/s/$/ $HOST_ENTRY/" /etc/hosts
fi

URL="https://${Hostname}"
TIMEOUT=10
MAX_RETRIES=60

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

# vllm
URL="http://127.0.0.1:8000/v1/models"
TIMEOUT=10
MAX_RETRIES=180

# Only attempt wget if the service start was successful
if [ $success -eq 0 ]; then
    for ((i=1; i<=MAX_RETRIES; i++)); do
        wget --no-check-certificate --timeout=$TIMEOUT --tries=1 "$URL" >/dev/null 2>&1
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
