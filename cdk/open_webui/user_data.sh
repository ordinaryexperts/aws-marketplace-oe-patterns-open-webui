#!/bin/bash

mkdir -p /opt/oe/patterns

SECRET_NAME=$(aws secretsmanager describe-secret --secret-id ${SecretArn} --region ${AWS::Region} | jq -r .Name)
aws ssm get-parameter \
    --name "/aws/reference/secretsmanager/$SECRET_NAME" \
    --with-decryption \
    --query Parameter.Value \
    --region ${AWS::Region} \
| jq -r . > /opt/oe/patterns/secrets.json

WEBUI_SECRET_KEY=$(cat /opt/oe/patterns/secrets.json | jq -r .WEBUI_SECRET_KEY)

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

# NVMe Instance Store Setup
# Mount NVMe instance store for high-performance model caching
echo "Setting up NVMe instance store for model caching..."

# Detect NVMe instance store device (typically nvme1n1 on g6e instances)
# nvme0n1 is the root volume, nvme1n1 is the instance store
NVME_DEVICE="/dev/nvme1n1"

if [ -b "$NVME_DEVICE" ]; then
    echo "Found NVMe instance store: $NVME_DEVICE"

    # Format the device (this is ephemeral storage, safe to format on each boot)
    mkfs.ext4 -F "$NVME_DEVICE"

    # Create mount point and mount
    mkdir -p /mnt/instance-store
    mount "$NVME_DEVICE" /mnt/instance-store
    chmod 777 /mnt/instance-store

    # Create Hugging Face cache directory on instance store
    mkdir -p /mnt/instance-store/huggingface
    chmod 777 /mnt/instance-store/huggingface

    # Create symlink from default cache location to instance store
    # This ensures all Hugging Face downloads go directly to NVMe
    mkdir -p /root/.cache
    ln -s /mnt/instance-store/huggingface /root/.cache/huggingface

    echo "NVMe instance store configured at /mnt/instance-store"
    echo "Hugging Face cache will use: /root/.cache/huggingface -> /mnt/instance-store/huggingface"
else
    echo "WARNING: No NVMe instance store found at $NVME_DEVICE"
    echo "Model will be downloaded to EBS (slower performance)"
    mkdir -p /root/.cache/huggingface
fi

# VLLM

# custom vllm config - fetch additional CLI arguments from SSM Parameter Store
CUSTOM_VLLM_ARGS=""
if [[ "${CustomVllmConfigParameterArn}" != "" ]]; then
    echo "Fetching custom vLLM config from ${CustomVllmConfigParameterArn}..."
    CUSTOM_VLLM_ARGS=$(aws ssm get-parameter --name "${CustomVllmConfigParameterArn}" --with-decryption --output text --query Parameter.Value)
    echo "Custom vLLM args: $CUSTOM_VLLM_ARGS"
fi

# Tool-calling parser is model-specific. Default per model family:
#   Qwen / nvidia/OpenReasoning-Nemotron-* -> hermes
#   microsoft/Phi-4-mini-*                 -> phi4_mini_json
#   openai/gpt-oss-*                       -> gpt_oss
#   microsoft/phi-4 (full)                 -> no built-in parser; tool calling disabled
# Users can still override via CustomVllmConfigParameterArn (CUSTOM_VLLM_ARGS is appended last).
case "${ModelName}" in
    Qwen/*|nvidia/OpenReasoning-Nemotron-*)
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser hermes"
        ;;
    microsoft/Phi-4-mini-*)
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser phi4_mini_json"
        ;;
    openai/gpt-oss-*)
        TOOL_CALL_ARGS="--enable-auto-tool-choice --tool-call-parser gpt_oss"
        ;;
    *)
        TOOL_CALL_ARGS=""
        ;;
esac
echo "Default tool-call args for ${ModelName}: $TOOL_CALL_ARGS"

# Default max-model-len + KV cache dtype.
# microsoft/phi-4 (full) maxes at 16K natively; everything else here supports 32K+.
# fp8 KV cache roughly doubles the available KV-cache capacity, which agentic clients
# (opencode, aider) need because their tool-definition prompts are 10-15K tokens.
case "${ModelName}" in
    microsoft/phi-4)
        DEFAULT_MAX_MODEL_LEN_ARGS="--max-model-len 16384 --kv-cache-dtype fp8"
        ;;
    *)
        DEFAULT_MAX_MODEL_LEN_ARGS="--max-model-len 32768 --kv-cache-dtype fp8"
        ;;
esac
echo "Default max-model-len args for ${ModelName}: $DEFAULT_MAX_MODEL_LEN_ARGS"

cat <<EOF > /root/start-vllm.sh
#!/bin/bash

# Activate the Python virtual environment
source /opt/open-webui-venv/bin/activate || { echo "Failed to activate venv '/opt/open-webui-venv'"; exit 1; }

# Ensure vllm is installed
if ! command -v vllm &> /dev/null; then
    echo "vllm not found. Make sure it is installed in the venv."
    exit 1
fi

# Start vllm with GPU memory utilization flag
# vLLM will automatically download the model to /root/.cache/huggingface (symlinked to NVMe)
# on first startup. This typically takes 5-10 minutes for ~29GB models when downloading to NVMe.
# Model loading from NVMe takes ~3 minutes after download completes.
vllm serve ${ModelName} --gpu-memory-utilization 0.95 $TOOL_CALL_ARGS $DEFAULT_MAX_MODEL_LEN_ARGS $CUSTOM_VLLM_ARGS
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
Environment="PATH=/opt/open-webui-venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

# Open WebUI

cat <<EOF > /root/start-open-webui.sh
#!/bin/bash

# Activate the Python virtual environment
source /opt/open-webui-venv/bin/activate || { echo "Failed to activate venv '/opt/open-webui-venv'"; exit 1; }

# Ensure open-webui is installed
if ! command -v open-webui &> /dev/null; then
    echo "open-webui not found. Make sure it is installed in the venv."
    exit 1
fi

# Set up environment variables
export DATA_DIR=/data
export WEBUI_SECRET_KEY=$WEBUI_SECRET_KEY
export OPENAI_API_BASE_URL=http://127.0.0.1:8000/v1
export ENABLE_SIGNUP=true

# CORS security configuration - restrict to our domain only
export CORS_ALLOW_ORIGIN=https://${Hostname}
export WEBUI_URL=https://${Hostname}

# Fetch and apply custom environment variables from SSM Parameter Store
# Note: --region is required because systemd context does not auto-detect region from IMDS reliably.
# Wrapping in `timeout 30` so a slow IMDS or transient SSM error cannot hang service startup indefinitely.
if [[ "${CustomOpenWebuiConfigParameterArn}" != "" ]]; then
  echo "Fetching custom Open WebUI config from ${CustomOpenWebuiConfigParameterArn}..."
  CUSTOM_OPENWEBUI_ENV=\$(timeout 30 aws ssm get-parameter --region ${AWS::Region} --name "${CustomOpenWebuiConfigParameterArn}" --with-decryption --output text --query Parameter.Value)
  rc=\$?
  if [[ \$rc -eq 0 && -n "\$CUSTOM_OPENWEBUI_ENV" ]]; then
    echo "Applying custom Open WebUI configuration..."
    while IFS= read -r line; do
      # Skip empty lines and comments
      if [[ -n "\$line" && ! "\$line" =~ ^[[:space:]]*# ]]; then
        # Extract variable name for logging (before = sign)
        var_name=\$(echo "\$line" | cut -d'=' -f1)
        echo "  Setting environment variable: \$var_name"
        export "\$line"
      fi
    done <<< "\$CUSTOM_OPENWEBUI_ENV"
    echo "Custom Open WebUI configuration applied successfully"
  else
    echo "No custom Open WebUI config applied (rc=\$rc)"
  fi
else
  echo "No custom Open WebUI config parameter ARN provided"
fi

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
Environment="PATH=/opt/open-webui-venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

# Wait for vLLM to be ready before signaling CloudFormation
echo "Waiting for vLLM model loading to complete (this may take 60+ minutes)..."
URL="http://127.0.0.1:8000/v1/models"
TIMEOUT=10
MAX_RETRIES=360

# Only attempt wget if the Open WebUI service start was successful
if [ $success -eq 0 ]; then
    for ((i=1; i<=MAX_RETRIES; i++)); do
        wget --no-check-certificate --timeout=$TIMEOUT --tries=1 "$URL" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo "Successfully reached $URL - vLLM is ready!"
            success=0  # Indicate success
            break
        fi
        echo "Attempt $i/$MAX_RETRIES to reach $URL failed...retrying in $TIMEOUT seconds..."
        sleep $TIMEOUT
    done

    if [ $i -gt $MAX_RETRIES ]; then
        echo "Failed to reach $URL after $MAX_RETRIES attempts - vLLM failed to load"
        success=1  # Indicate failure
    fi
else
    echo "Skipping vLLM checks since Open WebUI failed to start."
    success=1  # Indicate failure
fi

# Signal CloudFormation after vLLM is ready
echo "Signaling CloudFormation with status (success=$success)"
cfn-signal --exit-code $success --stack ${AWS::StackName} --resource Asg --region ${AWS::Region}
