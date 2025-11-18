# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS Marketplace pattern that deploys Open WebUI with vLLM for running LLMs on AWS. The project consists of:

1. **Custom AMI** built with Packer (Ubuntu 22.04 with CUDA, cuDNN, vLLM, and Open WebUI pre-installed)
2. **CDK Infrastructure** (Python) that synthesizes to CloudFormation templates
3. **GPU-accelerated inference** using NVIDIA GPUs (g6e instance family)

The infrastructure includes: VPC, Auto Scaling Group (EC2 with GPU), Application Load Balancer, Route53, ACM, and supporting services (IAM, CloudWatch, SSM).

## Development Environment

All development is done inside Docker containers via docker-compose to ensure consistency:

- `devenv` service: Main development environment with CDK, AWS CLI, Python, and all required tools
- `ami` service: Packer environment for building custom AMIs

**Never run CDK, Packer, or other build commands directly on the host.** Always use `make` targets which wrap docker-compose.

### Using AWS Profiles

The `~/.aws` directory is mounted into the container, so you can use AWS profiles directly:

```bash
AWS_PROFILE=oe-patterns-dev make deploy
```

Alternatively, you can export the profile:
```bash
export AWS_PROFILE=oe-patterns-dev
make deploy
```

## Common Commands

### Build and Setup
- `make build` - Build the devenv Docker image
- `make rebuild` - Rebuild devenv without cache
- `make bash` - Start an interactive bash session in devenv container

### CDK Operations
- `make synth` - Synthesize CloudFormation template
- `make synth-to-file` - Synthesize template and save to `dist/template.yaml`
- `make diff` - Show differences between deployed stack and current code
- `make deploy` - Deploy the stack to AWS (dev environment with hardcoded parameters)
- `make destroy` - Destroy the deployed stack
- `make cdk-bootstrap` - Bootstrap CDK in the AWS account

### Testing
- `make lint` - Run linting checks

### AMI Building
- `make ami-ec2-build TEMPLATE_VERSION=<version>` - Build AMI with Packer
- `make ami-ec2-copy AMI_ID=<id>` - Copy AMI to other regions
- `make ami-docker-bash` - Interactive bash session in AMI container

### Cleanup
- `make clean` - Clean up test resources
- `make clean-snapshots-tcat` - Clean up taskcat snapshots
- `make clean-logs-tcat` - Clean up taskcat logs
- `make clean-buckets-tcat` - Clean up taskcat S3 buckets

## Architecture

### CDK Stack Structure

The main CDK stack (`cdk/open_webui/open_webui_stack.py`) is composed using reusable constructs from the `oe-patterns-cdk-common` library. Key components:

1. **Vpc** - Creates VPC or uses existing one via parameters
2. **Dns** - Route53 hosted zone integration (parameter-driven)
3. **Alb** - Application Load Balancer with ACM certificate
4. **Asg** - Auto Scaling Group with custom AMI, configured as singleton (single instance)

### AMI Configuration

The AMI is built via Packer (`packer/ami.json`) using `packer/ubuntu_2204_appinstall.sh`. It pre-installs:
- CUDA 12.8.1 with NVIDIA driver 570.124.06
- cuDNN 9.8.0
- Miniconda with Python 3.11 environment
- vLLM (for GPU-accelerated LLM inference)
- Open WebUI (web interface for LLM interaction)
- nginx as reverse proxy with self-signed SSL
- CloudWatch agent
- AWS Systems Manager agent

The AMI ID is hardcoded in `cdk/open_webui/open_webui_stack.py` as the `AMI_ID` constant and must be updated when building new AMIs.

### User Data

EC2 instances run `cdk/open_webui/user_data.sh` on boot, which:
- Configures CloudWatch Logs
- Generates self-signed SSL certificate for nginx
- Configures nginx to proxy HTTPS traffic to Open WebUI on port 8080
- Creates and starts systemd services for vLLM and Open WebUI
- Retrieves optional custom configuration from SSM Parameter Store
- Waits for services to be ready before signaling CloudFormation success

### Parameter-Driven Design

The stack uses CloudFormation parameters extensively (see `CfnParameter` calls in `open_webui_stack.py`). Key parameters:
- `Model` - The LLM to load from dropdown of tested open-source models:
  - **General purpose**: microsoft/phi-4 (14B), Qwen/Qwen2.5-Coder-7B/14B/32B-Instruct
  - **Reasoning models**: microsoft/Phi-4-mini-reasoning (3.8B), nvidia/OpenReasoning-Nemotron-7B/14B/32B
- `ModelOverride` - Custom model name in Hugging Face format to override the dropdown
- `CustomOpenWebuiConfigParameterArn` - Optional SSM Parameter ARN for custom Open WebUI config
- `CustomVllmConfigParameterArn` - Optional SSM Parameter ARN for custom vLLM config
- `DnsHostname` / `DnsRoute53HostedZoneName` - DNS configuration
- `AlbCertificateArn` - ACM certificate for HTTPS
- `AlbIngressCidr` - IP ranges allowed to access the site
- `AsgInstanceType` - GPU instance type (g6e.xlarge, g6e.2xlarge, etc.)
- `AsgAmiId` - AMI ID to use for EC2 instances
- `AsgReprovisionString` - Forces ASG instance replacement when changed

### Instance Types

This stack is designed for GPU instances in the g6e family:
- g6e.xlarge (24 GB GPU memory)
- g6e.2xlarge (48 GB GPU memory)
- g6e.4xlarge (96 GB GPU memory)
- g6e.8xlarge (192 GB GPU memory)
- g6e.16xlarge (384 GB GPU memory)

The instance type determines which models can be loaded. Larger models require more GPU memory.

## Important Patterns

### Version Management
Template version is determined by:
1. `TEMPLATE_VERSION` environment variable (if set)
2. `git describe` output (in git repos)
3. Falls back to "CICD" in CI environments

### Data Persistence
Open WebUI data is stored on a separate EBS volume (mounted at `/data`) that persists across instance replacements. This is managed by the `Asg` construct with `use_data_volume=True`.

### Service Architecture
Two systemd services run on each instance:
1. **vllm.service** - Runs vLLM server on port 8000, loading the specified model
2. **open-webui.service** - Runs Open WebUI on port 8080, configured to use vLLM as the OpenAI API backend

nginx proxies HTTPS traffic from the ALB to Open WebUI.

### Singleton Pattern
The ASG is configured as a singleton (`singleton=True`), meaning it maintains exactly one instance. This simplifies the architecture but means the service is not highly available during instance replacements.

### Health Checks
- ALB health check: `/elb-check` endpoint (returns 200 OK)
- Instance readiness: User data script waits for both Open WebUI and vLLM to respond before signaling success

## Git Workflow

- Main branch: `main`
- Development branch: `feature/initial-dev` (current)

## Dependencies

### Python CDK Dependencies
Defined in `cdk/requirements.txt`:
- `aws-cdk-lib==2.120.0`
- `constructs>=10.0.0,<11.0.0`
- `oe-patterns-cdk-common@4.2.4` (from GitHub, contains reusable constructs)

### Docker Base Image
The devenv service builds from `ordinaryexperts/aws-marketplace-patterns-devenv` (version specified in Dockerfile), which contains CDK, Python, AWS CLI, and other tools.

## Debugging and Troubleshooting

### Finding CloudWatch Log Groups for a Deployment

When troubleshooting a deployment, you need to access the CloudWatch logs for the EC2 instances. The log groups are created as part of the CloudFormation stack.

**Step 1: Get the log groups from CloudFormation**

```bash
export AWS_PROFILE=patterns-dev
STACK_NAME="oe-patterns-open-webui-dylan"  # Or your stack name

# List all log groups in the stack
aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --query 'StackResources[?ResourceType==`AWS::Logs::LogGroup`].[LogicalResourceId,PhysicalResourceId]' \
  --output table
```

This will show you two log groups:
- **AsgAppLogGroup** - Application logs (vLLM, Open WebUI, nginx)
- **AsgSystemLogGroup** - System logs (syslog, user data script execution)

**Step 2: Find log streams for a specific instance**

```bash
# Get the instance ID from CloudFormation events or EC2
INSTANCE_ID="i-0123456789abcdef0"  # Replace with your instance ID

# List app log streams for the instance
aws logs describe-log-streams \
  --log-group-name "oe-patterns-open-webui-dylan-AsgAppLogGroup-XXXXX" \
  --log-stream-name-prefix "$INSTANCE_ID" \
  --query 'logStreams[*].logStreamName' \
  --output table
```

**Step 3: View specific logs**

Application log streams follow the pattern: `{instance-id}-{log-file-path}`

Common log streams:
- `{instance-id}-/var/log/vllm.log` - vLLM server logs (model loading, inference)
- `{instance-id}-/var/log/open-webui.log` - Open WebUI application logs
- `{instance-id}-/var/log/nginx/error.log` - nginx errors
- `{instance-id}-/var/log/nginx/access.log` - nginx access logs

```bash
# View vLLM logs (last 100 lines)
aws logs tail "oe-patterns-open-webui-dylan-AsgAppLogGroup-XXXXX" \
  --log-stream-name "$INSTANCE_ID-/var/log/vllm.log" \
  --format short \
  --since 1h

# Follow logs in real-time
aws logs tail "oe-patterns-open-webui-dylan-AsgAppLogGroup-XXXXX" \
  --follow \
  --format short
```

**Common Debugging Scenarios:**

1. **Instance fails to signal CloudFormation** - Check system logs for user data script errors
2. **Model loading failures** - Check `/var/log/vllm.log` for CUDA, VRAM, or model download errors
3. **Open WebUI not accessible** - Check nginx logs and `/var/log/open-webui.log`
4. **No logs appear** - Instance failed before CloudWatch agent started; check EC2 console logs

## Files to Update When Releasing

1. `cdk/open_webui/open_webui_stack.py` - Update `AMI_ID` constant
2. `CHANGELOG.md` - Document changes
3. Git tag with version number
