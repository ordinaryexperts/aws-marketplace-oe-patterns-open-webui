SCRIPT_VERSION=1.7.6
SCRIPT_PREINSTALL=ubuntu_2204_2404_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2204_2404_postinstall.sh
OPEN_WEBUI_VERSION=0.6.36
PYTHON_VERSION=3.12

# preinstall steps
echo "Downloading preinstall script (version $SCRIPT_VERSION)..."
curl -sS -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
if [ ! -f "$SCRIPT_PREINSTALL" ]; then
    echo "ERROR: Failed to download preinstall script"
    exit 1
fi
echo "Downloaded $SCRIPT_PREINSTALL successfully"
chmod +x $SCRIPT_PREINSTALL
echo "Executing preinstall script..."
./$SCRIPT_PREINSTALL
PREINSTALL_EXIT_CODE=$?
if [ $PREINSTALL_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Preinstall script exited with code $PREINSTALL_EXIT_CODE"
    exit 1
fi
echo "Preinstall script completed successfully"

# Verify CloudWatch agent was installed by preinstall
echo "Verifying CloudWatch agent installation..."
if [ -f /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then
    echo "CloudWatch agent binary found at /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent"
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent -version
else
    echo "ERROR: CloudWatch agent binary NOT found - preinstall may have failed"
    echo "Checking if collectd was installed..."
    if dpkg -l | grep -q collectd; then
        echo "collectd is installed"
    else
        echo "ERROR: collectd is also missing"
    fi
    exit 1
fi

rm $SCRIPT_PREINSTALL

# aws cloudwatch - configure after preinstall has installed the agent
echo "Configuring CloudWatch agent..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat <<EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "collectd": {
        "metrics_aggregation_interval": 60
      },
      "disk": {
        "measurement": ["used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      }
    },
    "append_dimensions": {
      "ImageId": "\${aws:ImageId}",
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}",
      "AutoScalingGroupName": "\${aws:AutoScalingGroupName}"
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/dpkg.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/dpkg.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/apt/history.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/apt/history.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/amazon-ssm-agent.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/amazon-ssm-agent.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/amazon/ssm/errors.log",
            "log_group_name": "ASG_SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/amazon/ssm/errors.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "ASG_APP_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/nginx/access.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "ASG_APP_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/nginx/error.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/open-webui.log",
            "log_group_name": "ASG_APP_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/open-webui.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/vllm.log",
            "log_group_name": "ASG_APP_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}-/var/log/vllm.log",
            "timezone": "UTC"
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF

# rust
echo "Installing Rust..."
apt-get install -y -qq rustc cargo > /dev/null

# nvtop (GPU monitoring tool)
echo "Installing nvtop..."
apt-get install -y -qq nvtop > /dev/null

# CUDA and matching NVIDIA driver
echo "Downloading CUDA repository configuration..."
wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-ubuntu2404.pin
mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600

echo "Downloading CUDA 12.8.1 installer (this may take a few minutes)..."
wget -q https://developer.download.nvidia.com/compute/cuda/12.8.1/local_installers/cuda-repo-ubuntu2404-12-8-local_12.8.1-570.124.06-1_amd64.deb
echo "CUDA installer downloaded successfully"
echo "Installing CUDA repository package..."
dpkg -i cuda-repo-ubuntu2404-12-8-local_12.8.1-570.124.06-1_amd64.deb
cp /var/cuda-repo-ubuntu2404-12-8-local/cuda-*-keyring.gpg /usr/share/keyrings/
apt-get update -qq

echo "Installing CUDA toolkit and driver (this will take several minutes)..."
apt-get -y install cuda > /dev/null

# cuDNN
echo "Downloading cuDNN 9.8.0 installer (this may take a few minutes)..."
wget -q https://developer.download.nvidia.com/compute/cudnn/9.8.0/local_installers/cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
echo "cuDNN installer downloaded successfully"
echo "Installing cuDNN repository package..."
dpkg -i cudnn-local-repo-ubuntu2404-9.8.0_1.0-1_amd64.deb
cp /var/cudnn-local-repo-ubuntu2404-9.8.0/cudnn-*-keyring.gpg /usr/share/keyrings/
apt-get update -qq
echo "Installing cuDNN..."
apt-get -y install cudnn cudnn-cuda-12 > /dev/null

# Python virtual environment (using system Python 3.12 from Ubuntu 24.04)
echo "Installing python3-venv package..."
apt-get install -y -qq python3-venv > /dev/null
echo "Setting up Python virtual environment..."
python3 --version  # Should be 3.12.x on Ubuntu 24.04
python3 -m venv /opt/open-webui-venv
echo "Installing Python packages (flashinfer, vllm, huggingface_hub)..."
/opt/open-webui-venv/bin/pip install --quiet --upgrade pip
/opt/open-webui-venv/bin/pip install --quiet huggingface_hub
/opt/open-webui-venv/bin/pip install --quiet flashinfer-python
/opt/open-webui-venv/bin/pip install --quiet vllm

# NOTE: Model pre-downloading has been removed from AMI build
# Models will be downloaded directly to NVMe instance store on first boot
# This approach is faster overall:
#   - AMI builds are faster (~20 minutes saved)
#   - AMI size is smaller
#   - Model downloads directly to high-speed NVMe storage (~5-10 min download + 3 min load)
#   - vs old approach: EBS pre-download in AMI + 55 min copy to NVMe + 3 min load
# See user_data.sh for NVMe setup and automatic model downloading

# open-webui deps
echo "Installing Open WebUI dependencies..."
apt-get -y -qq install build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev curl git \
        libncursesw5-dev xz-utils tk-dev libxml2-dev \
        libxmlsec1-dev libffi-dev liblzma-dev ffmpeg > /dev/null

echo "Installing Open WebUI $OPEN_WEBUI_VERSION..."
/opt/open-webui-venv/bin/pip install --quiet open-webui==$OPEN_WEBUI_VERSION

# nginx
echo "Installing nginx..."
apt-get install -y -qq nginx > /dev/null

# Verify AWS CLI is installed and accessible
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found in PATH, installing..."
    cd /tmp
    curl -sS https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
    unzip -q -o awscliv2.zip
    ./aws/install --update > /dev/null
    cd -
fi
echo "AWS CLI version: $(aws --version)"

# Verify CFN tools are installed
if ! command -v cfn-signal &> /dev/null; then
    echo "CFN tools not found, installing..."
    pip install --quiet --break-system-packages https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz
fi
echo "CFN tools installed: $(which cfn-signal)"

# Create check-secrets.py utility script
echo "Creating check-secrets.py utility script..."
cat > /root/check-secrets.py << 'PYTHON_SCRIPT_EOF'
#!/usr/bin/env python3
import boto3
import json
import secrets
import sys

def generate_secret_key():
    """Generate a secure 32-byte hex string for WEBUI_SECRET_KEY"""
    return secrets.token_hex(32)

def main():
    if len(sys.argv) != 3:
        print("Usage: check-secrets.py <region> <secret_arn>")
        sys.exit(1)

    region = sys.argv[1]
    secret_arn = sys.argv[2]

    client = boto3.client('secretsmanager', region_name=region)

    try:
        # Try to get the secret
        response = client.get_secret_value(SecretId=secret_arn)
        secret_data = json.loads(response['SecretString'])

        # Check if WEBUI_SECRET_KEY exists
        if 'WEBUI_SECRET_KEY' not in secret_data or not secret_data['WEBUI_SECRET_KEY']:
            print("WEBUI_SECRET_KEY not found or empty, generating...")
            secret_data['WEBUI_SECRET_KEY'] = generate_secret_key()

            client.update_secret(
                SecretId=secret_arn,
                SecretString=json.dumps(secret_data)
            )
            print("Secret updated successfully with WEBUI_SECRET_KEY")
        else:
            print("WEBUI_SECRET_KEY already exists")

    except client.exceptions.ResourceNotFoundException:
        print(f"Secret {secret_arn} not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error checking/updating secret: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
PYTHON_SCRIPT_EOF
chmod +x /root/check-secrets.py
echo "check-secrets.py created successfully"

# post install steps
echo "Downloading postinstall script..."
curl -sS -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
