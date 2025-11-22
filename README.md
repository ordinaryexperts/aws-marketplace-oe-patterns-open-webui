# aws-marketplace-oe-patterns-open-webui

Deploy Open WebUI on AWS with vLLM backend for GPU-accelerated LLM inference.

## Overview

This pattern deploys Open WebUI with vLLM on AWS infrastructure, providing:
- GPU-accelerated model inference using vLLM
- Web interface for model interaction via Open WebUI
- OpenAI-compatible API for third-party tool integration
- Support for Qwen, Microsoft Phi, and NVIDIA Nemotron models

## Architecture

- **Frontend**: Open WebUI web interface
- **Backend**: vLLM inference server with OpenAI-compatible API
- **Infrastructure**: AWS EC2 with GPU support (G6e instances)
- **Networking**: Application Load Balancer with HTTPS

## Using Aider with Open WebUI

[Aider](https://aider.chat) is an AI pair programming tool that works with Open WebUI's OpenAI-compatible API.

### Recommended Model for Aider

Based on 2025 benchmarks and research, **Qwen/Qwen2.5-Coder-7B-Instruct** is the best choice for aider when using this deployment:

- Industry benchmarks show top models for aider are Claude 3.5 Sonnet (64% accuracy) and DeepSeek R1
- Among open-source models available in this deployment, **Qwen 2.5 Coder series** provides the best coding performance
- The 7B model offers excellent speed on g6e.xlarge instances with strong coding capabilities
- Larger Qwen models (14B, 32B) are available for more complex tasks requiring deeper reasoning

### Prerequisites

1. Install aider:
```bash
pip install aider-chat
```

2. Get your Open WebUI API key:
   - Log into Open WebUI at your deployment URL
   - Navigate to Settings → Account
   - Create a new API key

### Configuration

Set up environment variables:

```bash
export OPENAI_API_KEY='your-open-webui-api-key'
export OPENAI_API_BASE='https://your-deployment-url/api'
```

### Basic Usage

Start aider in your project directory:

```bash
aider --model 'openai/Qwen/Qwen2.5-Coder-7B-Instruct'
```

**Important**: Prefix the model name with `openai/` so litellm recognizes it as an OpenAI-compatible endpoint.

### Available Models

The models below have been tested and categorized by minimum instance requirements:

**Coding Models (Best for Aider):**
- **Qwen/Qwen2.5-Coder-7B-Instruct** ✓ Tested on g6.xlarge - Fast, efficient coding model (Recommended)
- **Qwen/Qwen2.5-Coder-14B-Instruct** - Larger model with better reasoning (requires g6.2xlarge or larger)
- **Qwen/Qwen2.5-Coder-32B-Instruct** - Most capable coding model (requires g6.4xlarge or larger)

**Reasoning Models:**
- **microsoft/Phi-4-mini-reasoning** ✓ Tested on g6e.xlarge - 3.8B reasoning model, very fast
- **nvidia/OpenReasoning-Nemotron-7B** ✓ Tested on g6e.xlarge - 7B reasoning model, 131K context
- **nvidia/OpenReasoning-Nemotron-14B** - 14B reasoning model (requires g6.2xlarge or larger)
- **nvidia/OpenReasoning-Nemotron-32B** - 32B reasoning model (requires g6.4xlarge or larger)

**General Purpose Models:**
- **microsoft/phi-4** ✓ Tested on g6e.xlarge - 14B general model with strong performance (requires g6.2xlarge or larger)

To use a different model:

```bash
# List available models
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  https://your-deployment-url/api/models

# Use specific model with aider
aider --model 'openai/your-model-name'
```

### Advanced Configuration

You can create a `.aider.conf.yml` file in your project:

```yaml
openai-api-base: https://your-deployment-url/api
openai-api-key: sk-your-api-key-here
model: openai/Qwen/Qwen2.5-Coder-7B-Instruct
```

### Tips for Best Performance

1. **Model Selection**: Start with the 7B model for fast iterations, use larger models for complex tasks
2. **Context Window**: Qwen models support large context windows, making them ideal for working with multiple files
3. **Git Integration**: Aider works best in git repositories - it uses git to track changes
4. **Model Warming**: First request may be slower as the model loads - subsequent requests are faster

### Troubleshooting

#### "LLM Provider NOT provided" Error

Make sure to prefix your model name with `openai/`:
```bash
# Wrong
aider --model 'Qwen/Qwen2.5-Coder-7B-Instruct'

# Correct
aider --model 'openai/Qwen/Qwen2.5-Coder-7B-Instruct'
```

#### Authentication Errors

Verify your API key is valid:
```bash
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  $OPENAI_API_BASE/models
```

#### Slow Response Times

- Ensure you're using an appropriately sized GPU instance
- Check that the model matches your instance type (7B → g6e.xlarge, 14B → g6e.2xlarge, etc.)
- First request after model load will be slower

## API Documentation

### Get Available Models

```bash
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  https://your-deployment-url/api/models
```

### Chat Completion

```bash
curl -X POST https://your-deployment-url/api/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-Coder-7B-Instruct",
    "messages": [
      {"role": "user", "content": "Write a hello world function in Python"}
    ]
  }'
```

### Streaming Completion

```bash
curl -X POST https://your-deployment-url/api/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-Coder-7B-Instruct",
    "messages": [
      {"role": "user", "content": "Explain async/await"}
    ],
    "stream": true
  }'
```

## Model Configuration

Configure the deployed model via CDK parameters:

- `AsgInstanceType`: GPU instance type (default: g6.xlarge)
- `AsgAmiId`: AMI with the desired model pre-baked
- `Model`: Select from pre-tested models or use ModelOverride for custom models

### Instance Type Selection

The deployment supports both G6 (NVIDIA L4) and G6e (NVIDIA L40S) instance families:

**G6 Instances (NVIDIA L4 - Cost-Optimized):**
- g6.xlarge (default) - $0.805/hour - Best for 7B models, single-user development
- g6.2xlarge - $1.610/hour - 14B models, moderate concurrency
- g6.4xlarge - $3.220/hour - 32B models or high concurrency
- g6.8xlarge - $6.440/hour - Multiple large models
- g6.16xlarge - $12.880/hour - Enterprise workloads

**G6e Instances (NVIDIA L40S - Performance-Optimized):**
- g6e.xlarge - $1.861/hour - 2.9x memory bandwidth, 48GB VRAM
- g6e.2xlarge - $3.722/hour - Enhanced performance for 14B+ models
- g6e.4xlarge - $7.444/hour - Production deployments
- g6e.8xlarge - $14.888/hour - High-throughput serving
- g6e.16xlarge - $29.776/hour - Maximum performance

**Recommendation by Use Case:**
- **Development/Testing (7B models):** g6.xlarge (default) - Most cost-effective
- **Production (7B models, multi-user):** g6e.xlarge - Better throughput
- **14B models:** g6.2xlarge (dev) or g6e.2xlarge (prod)
- **32B models:** g6.4xlarge (dev) or g6e.4xlarge (prod)

**Cost Savings:** Using g6.xlarge instead of g6e.xlarge saves ~$760/month (57%) with minimal performance impact for single-user workloads.

## Custom Configuration

You can customize both vLLM and Open WebUI settings by providing configuration via AWS Systems Manager Parameter Store. This allows you to override default settings without modifying the CDK code.

### Creating Configuration Parameters

Create SSM Parameter Store SecureString parameters containing your custom configuration:

```bash
# Custom vLLM configuration (additional CLI arguments)
aws ssm put-parameter \
  --name "/oe-patterns/open-webui/${USER}/vllm-config" \
  --type "SecureString" \
  --value "--max-model-len 8192 --max-num-seqs 256"

# Custom Open WebUI configuration (environment variables)
aws ssm put-parameter \
  --name "/oe-patterns/open-webui/${USER}/openwebui-config" \
  --type "SecureString" \
  --value "WEBUI_NAME='My Custom Instance'
ENABLE_SIGNUP=false
DEFAULT_USER_ROLE=pending"
```

### Using Custom Configurations in Deployment

Pass the parameter ARNs when deploying:

```bash
# In Makefile
--parameters CustomVllmConfigParameterArn=arn:aws:ssm:us-east-1:ACCOUNT_ID:parameter/path/to/vllm-config \
--parameters CustomOpenWebuiConfigParameterArn=arn:aws:ssm:us-east-1:ACCOUNT_ID:parameter/path/to/openwebui-config
```

Or via CDK CLI:

```bash
cdk deploy \
  --parameters CustomVllmConfigParameterArn=arn:aws:ssm:...:parameter/vllm-config \
  --parameters CustomOpenWebuiConfigParameterArn=arn:aws:ssm:...:parameter/openwebui-config
```

### vLLM Configuration Options

The vLLM configuration parameter accepts additional command-line arguments that are appended to the `vllm serve` command. Common options include:

**Performance Tuning:**
- `--max-model-len 8192` - Override maximum sequence length
- `--max-num-seqs 256` - Maximum number of sequences to process in parallel
- `--gpu-memory-utilization 0.95` - GPU memory utilization (default: 0.95)
- `--swap-space 4` - CPU swap space size in GiB

**Quantization:**
- `--quantization awq` - Enable AWQ quantization
- `--quantization gptq` - Enable GPTQ quantization

**Advanced:**
- `--tensor-parallel-size 2` - Number of GPUs for tensor parallelism
- `--enable-prefix-caching` - Enable automatic prefix caching
- `--disable-log-stats` - Disable logging statistics

See the [vLLM documentation](https://docs.vllm.ai/en/latest/serving/openai_compatible_server.html) for the complete list of options.

### Open WebUI Configuration Options

The Open WebUI configuration parameter accepts environment variable assignments, one per line. Each line should be in the format `VAR_NAME=value`. Empty lines and lines starting with `#` (comments) are ignored.

**Note:** The deployment automatically adds `export` to each variable during instance startup, so you don't need to include it.

Common options include:

**Branding:**
- `WEBUI_NAME='Company Name'` - Custom instance name
- `WEBUI_URL='https://ai.example.com'` - Custom URL

**Authentication:**
- `ENABLE_SIGNUP=false` - Disable new user registration
- `DEFAULT_USER_ROLE=pending` - Set default role for new users (admin/user/pending)
- `ENABLE_LOGIN_FORM=false` - Disable login form (SSO only)

**Security:**
- `WEBUI_SECRET_KEY='your-secret-key'` - Custom secret key for sessions
- `ENABLE_API_KEY=true` - Enable API key authentication

**Storage:**
- `DATA_DIR=/data` - Data directory (should remain /data for persistence)

See the [Open WebUI documentation](https://docs.openwebui.com/getting-started/env-configuration) for the complete list of environment variables.

### Example: Production Configuration

```bash
# vLLM: Optimize for throughput
aws ssm put-parameter \
  --name "/oe-patterns/open-webui/prod/vllm-config" \
  --type "SecureString" \
  --value "--max-model-len 16384 --max-num-seqs 512 --enable-prefix-caching"

# Open WebUI: Lock down for production
aws ssm put-parameter \
  --name "/oe-patterns/open-webui/prod/openwebui-config" \
  --type "SecureString" \
  --value "WEBUI_NAME='Production AI Assistant'
ENABLE_SIGNUP=false
DEFAULT_USER_ROLE=pending
ENABLE_API_KEY=true"
```

### Updating Configuration

**Open WebUI:** Configuration is fetched from SSM Parameter Store every time the service starts. To apply updated configuration:

```bash
# Update the SSM parameter
aws ssm put-parameter \
  --name "/your/parameter/path" \
  --type "SecureString" \
  --value "WEBUI_NAME='Updated Name'" \
  --overwrite

# Restart the service to apply changes (via SSM on the instance)
aws ssm send-command \
  --instance-ids INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl restart open-webui"]'
```

**vLLM:** Configuration is embedded in the startup script at instance boot. To update vLLM configuration, you must redeploy the stack with a new `AsgReprovisionString` value to force instance replacement.

### Verification

After deployment, verify your custom configurations are applied:

```bash
# Check vLLM process arguments
aws ssm start-session --target INSTANCE_ID
ps aux | grep vllm

# Check Open WebUI environment
cat /proc/$(pgrep -f "open-webui serve")/environ | tr '\0' '\n' | grep -E 'WEBUI_NAME|ENABLE_SIGNUP'
```

You can also check the CloudWatch Logs for the instance to see the configuration being fetched during startup.

## Secret Management

This pattern uses AWS Secrets Manager to securely manage system-generated secrets, specifically the `WEBUI_SECRET_KEY` required for Open WebUI authentication.

### What is Managed

**System Secrets (AWS Secrets Manager):**
- `WEBUI_SECRET_KEY` - Automatically generated 32-byte hex string used for JWT authentication and session management
  - Generated automatically on first deployment
  - Persists across stack updates and instance replacements
  - Required for maintaining user sessions across Open WebUI updates

**User-Provided Secrets (SSM Parameter Store):**
- API keys like `OPENAI_API_KEY`, `GOOGLE_API_KEY`, etc. should be added to the `CustomOpenWebuiConfigParameterArn` SSM Parameter (see [Custom Configuration](#custom-configuration) section)
- SSM SecureString provides encryption at rest for these values

### How It Works

1. **First Deployment**: When the stack is deployed for the first time, a secret is created in AWS Secrets Manager with the stack name as a prefix (e.g., `oe-patterns-open-webui-dylan-secret-xxxxx`)

2. **Instance Startup**: On each instance boot, the `check-secrets.py` script:
   - Validates the secret exists
   - Checks if `WEBUI_SECRET_KEY` is present
   - If missing, generates a secure 32-byte hex string and updates the secret

3. **Secret Retrieval**: The instance fetches the secret value using AWS Systems Manager Parameter Store's reference to Secrets Manager: `/aws/reference/secretsmanager/<secret-name>`

4. **Application Use**: Open WebUI uses the `WEBUI_SECRET_KEY` for all authentication and session management

### Secret Rotation

To rotate the `WEBUI_SECRET_KEY` (which will invalidate all existing user sessions):

1. Update the secret in AWS Secrets Manager:
   ```bash
   SECRET_ARN=$(aws cloudformation describe-stacks \
     --stack-name oe-patterns-open-webui-dylan \
     --query 'Stacks[0].Outputs[?OutputKey==`SecretArn`].OutputValue' \
     --output text)

   NEW_KEY=$(openssl rand -hex 32)

   aws secretsmanager update-secret \
     --secret-id "$SECRET_ARN" \
     --secret-string "{\"WEBUI_SECRET_KEY\":\"$NEW_KEY\"}"
   ```

2. Restart the Open WebUI service (or terminate the instance to force replacement):
   ```bash
   # Via SSM Session Manager
   aws ssm start-session --target INSTANCE_ID
   systemctl restart open-webui
   ```

### Adding Other Secrets

For user-provided secrets like API keys:
- **Do NOT** add them to the Secrets Manager secret
- **Instead**, add them to the SSM Parameter Store config as documented in [Custom Configuration](#custom-configuration)
- Example:
  ```bash
  aws ssm put-parameter \
    --name "/oe-patterns/open-webui/${USER}/openwebui-config" \
    --type "SecureString" \
    --value "WEBUI_NAME=My Instance
  OPENAI_API_KEY=sk-...
  GOOGLE_API_KEY=..." \
    --overwrite
  ```

This keeps system-managed secrets (auto-generated) separate from user-provided configuration and secrets.
