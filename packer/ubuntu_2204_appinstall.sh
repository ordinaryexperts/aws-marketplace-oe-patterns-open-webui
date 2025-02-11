SCRIPT_VERSION=1.6.1
SCRIPT_PREINSTALL=ubuntu_2204_2404_preinstall.sh
SCRIPT_POSTINSTALL=ubuntu_2204_2404_postinstall.sh

# preinstall steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_PREINSTALL"
chmod +x $SCRIPT_PREINSTALL
./$SCRIPT_PREINSTALL
rm $SCRIPT_PREINSTALL

# aws cloudwatch
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
          }
        ]
      }
    },
    "log_stream_name": "{instance_id}"
  }
}
EOF

# Start setup
CUDA_HOME=/usr/local/cuda
HOME_DIR=/home/ubuntu

# rust
apt-get install -y rustc cargo

# NVIDIA drivers
wget https://us.download.nvidia.com/tesla/550.54.15/nvidia-driver-local-repo-ubuntu2204-550.54.15_1.0-1_arm64.deb
dpkg -i nvidia-driver-local-repo-ubuntu2204-550.54.15_1.0-1_arm64.deb
cp /var/nvidia-driver-local-repo-ubuntu2204-550.54.15/nvidia-driver-local-*-keyring.gpg /usr/share/keyrings/

# CUDA
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/sbsa/cuda-ubuntu2204.pin
mv cuda-ubuntu2204.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/12.4.1/local_installers/cuda-repo-ubuntu2204-12-4-local_12.4.1-550.54.15-1_arm64.deb
dpkg -i cuda-repo-ubuntu2204-12-4-local_12.4.1-550.54.15-1_arm64.deb
cp /var/cuda-repo-ubuntu2204-12-4-local/cuda-*-keyring.gpg /usr/share/keyrings/
apt-get update
apt-get -y install cuda-toolkit-12-4
apt-get install -y nvidia-driver-550-open
apt-get install -y cuda-drivers-550

CUDNN_VERSION=9.1.0.70
wget https://developer.download.nvidia.com/compute/cudnn/redist/cudnn/linux-sbsa/cudnn-linux-sbsa-${CUDNN_VERSION}_cuda12-archive.tar.xz
tar -xf cudnn-linux-sbsa-${CUDNN_VERSION}_cuda12-archive.tar.xz
cp -P cudnn-linux-sbsa-${CUDNN_VERSION}_cuda12-archive/include/* $CUDA_HOME/include/
cp -P cudnn-linux-sbsa-${CUDNN_VERSION}_cuda12-archive/lib/* $CUDA_HOME/lib64/
chmod a+r $CUDA_HOME/lib64/*

# Ollama
curl -L https://ollama.com/install.sh | sh
sleep 120 # give ollama a chance to come up...
OLLAMA_HOST="127.0.0.1:11434" ollama pull deepseek-r1:1.5b
OLLAMA_HOST="127.0.0.1:11434" ollama pull deepseek-r1:70b

# nginx
apt-get install -y nginx

# open-webui
groupadd -g 2000 app
useradd --create-home -c "Open WebUI User" -u 2000 -g app -s /bin/bash app

apt-get update
apt-get install -y build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev curl git \
        libncursesw5-dev xz-utils tk-dev libxml2-dev \
        libxmlsec1-dev libffi-dev liblzma-dev ffmpeg
curl https://raw.githubusercontent.com/pyenv/pyenv-installer/master/bin/pyenv-installer > /tmp/pyenv-installer
su - app -c "bash /tmp/pyenv-installer"

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /home/app/.bashrc
echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> /home/app/.bashrc
echo 'eval "$(pyenv init - bash)"' >> /home/app/.bashrc

echo 'export PYENV_ROOT="$HOME/.pyenv"' >> /home/app/.profile
echo '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"' >> /home/app/.profile
echo 'eval "$(pyenv init - bash)"' >> /home/app/.profile

su - app -c 'pyenv install 3.11.11'
su - app -c "pyenv global 3.11.11 && pip install open-webui"

# post install steps
curl -O "https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/$SCRIPT_VERSION/packer_provisioning_scripts/$SCRIPT_POSTINSTALL"
chmod +x "$SCRIPT_POSTINSTALL"
./"$SCRIPT_POSTINSTALL"
rm $SCRIPT_POSTINSTALL
