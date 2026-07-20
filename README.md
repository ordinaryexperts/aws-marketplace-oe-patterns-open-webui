# aws-marketplace-oe-patterns-open-webui

Deploy Open WebUI on AWS with vLLM backend for GPU-accelerated LLM inference.

## Overview

This pattern deploys Open WebUI with vLLM on AWS infrastructure, providing:
- GPU-accelerated model inference using vLLM
- Web interface for model interaction via Open WebUI
- OpenAI-compatible API for third-party tool integration
- Support for Qwen, Microsoft Phi, NVIDIA Nemotron, and Zhipu GLM models

## Demo

Watch a walkthrough of this pattern on YouTube: https://youtu.be/GLUVZANrQbc

## Architecture

- **Frontend**: Open WebUI web interface
- **Backend**: vLLM inference server with OpenAI-compatible API
- **Infrastructure**: AWS EC2 with GPU support (G6e instances)
- **Networking**: Application Load Balancer with HTTPS

## Available Models

The dropdown in the CFN `Model` parameter offers seven curated models. Each is tested with the baked-in vLLM tool-calling parser and `max-model-len` defaults so OpenAI-compatible coding agents (opencode, aider, etc.) work out of the box.

| Model | Min instance | License | Notes |
|---|---|---|---|
| **`Qwen/Qwen3-8B`** *(default)* | g6.xlarge (24 GB) | Apache 2.0 | Qwen3 family, native tool calling, fits smallest GPU. Recommended starting point. |
| `microsoft/Phi-4-mini-reasoning` | g6.xlarge (24 GB) | MIT | 3.8B reasoning model, very fast. |
| `microsoft/phi-4` | g6e.xlarge / g6.2xlarge (48 GB) | MIT | 14B general-purpose. 16K native context. |
| `openai/gpt-oss-20b` | g6e.xlarge / g6.2xlarge (48 GB) | Apache 2.0 | OpenAI's open release. Strong agentic. |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | g6e.2xlarge (48 GB at FP8) | Apache 2.0 | 30B-total/3B-active MoE. Purpose-built for agentic coding — best fit for opencode. |
| `nvidia/OpenReasoning-Nemotron-32B` | g6e.4xlarge (96 GB) | NVIDIA Open Model | 32B reasoning model, 131K context. |
| `zai-org/GLM-4-9B-0414` | g6e.xlarge / g6.2xlarge (48 GB) | MIT | 9B general-purpose, 32K context. No baked-in tool-call parser yet, so tool calling is off by default. |

Custom Hugging Face models can be loaded via the `ModelOverride` parameter — see CloudFormation parameter description.

To see the model currently loaded:

```bash
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  https://your-deployment-url/api/models
```

## Using OpenAI-Compatible Coding Agents

The deployment exposes two API base paths:

- `https://<hostname>/api` — Open WebUI's native chat completions (used by opencode, aider, and most OpenAI SDKs). Requires your Open WebUI API key.
- `https://<hostname>/api/v1` — same backend, OpenAI-spec `/v1/chat/completions` path. Use this if your tool auto-appends `/v1`.

### Get an API key

1. Sign up the first user in Open WebUI (becomes admin)
2. Settings → Account → API Keys → create a key (copy it; you can only see it once)

### opencode (https://opencode.ai)

opencode needs the OpenAI-compat backend declared as a custom provider — env vars alone aren't enough. Create `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "openwebui": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Open WebUI",
      "options": {
        "baseURL": "https://<your-hostname>/api",
        "apiKey": "sk-your-api-key"
      },
      "models": {
        "Qwen/Qwen3-8B": {
          "name": "Qwen3 8B",
          "tool_call": true,
          "reasoning": true,
          "limit": {
            "context": 32768,
            "output": 4096
          }
        }
      }
    }
  }
}
```

Then run:

```bash
opencode --model openwebui/Qwen/Qwen3-8B
```

**Tips:**
- `limit.output: 4096` is required — opencode's default of 32000 exceeds the model's effective output budget.
- `limit.context: 32768` matches the baked-in `--max-model-len 32768` so opencode won't try to send more context than vLLM accepts.
- For deeper agentic work, switch to `Qwen/Qwen3-Coder-30B-A3B-Instruct` on `g6e.2xlarge`.

### aider (https://aider.chat)

aider reads OpenAI env vars directly:

```bash
pip install aider-chat
export OPENAI_API_KEY='sk-your-open-webui-api-key'
export OPENAI_API_BASE='https://<your-hostname>/api'
aider --model 'openai/Qwen/Qwen3-8B'
```

Or via `.aider.conf.yml`:

```yaml
openai-api-base: https://<your-hostname>/api
openai-api-key: sk-your-api-key-here
model: openai/Qwen/Qwen3-8B
```

Note: prefix the model with `openai/` so litellm treats it as an OpenAI-compatible endpoint.

### Other tools

Any tool that supports an OpenAI-compatible base URL works the same way. Set base URL to `https://<your-hostname>/api`, use your Open WebUI API key, and reference the model by its full Hugging Face name (e.g. `Qwen/Qwen3-8B`).

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Wrong API key` from your tool | Tool is hitting api.openai.com (default), not your deployment | Set the tool's base-URL config to `https://<your-hostname>/api`. Env vars like `OPENAI_API_BASE` are SDK-specific — check your tool's docs. |
| `max_tokens=N cannot be greater than max_model_len` | Tool requested more output tokens than vLLM allows | Cap output in tool config (e.g. opencode's `limit.output: 4096`). |
| `prompt contains at least N input tokens, total exceeds max_model_len` | Tool's system prompt + tool definitions are too large for the model context | Increase `max-model-len` via SSM custom config (see "Custom Configuration") or pick a smaller agent profile. |
| `auto tool choice requires --enable-auto-tool-choice and --tool-call-parser` | vLLM started without tool-call flags | This pattern bakes them in by default. If you've overridden `CustomVllmConfigParameterArn`, ensure it includes the tool-call args or uses an empty value. |
| Slow first response | Model loading from NVMe + CUDA graph capture | Normal — takes 1–3 min after instance boot. Subsequent requests are fast. |

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

You can customize both vLLM and Open WebUI settings by providing configuration via AWS Systems Manager Parameter Store. The CFN parameters `CustomVllmConfigParameterArn` and `CustomOpenWebuiConfigParameterArn` accept SSM Parameter ARNs whose values are appended to the vLLM command line / exported as Open WebUI env vars at boot.

### Built-in vLLM defaults

To make a fresh deploy work for OpenAI-compatible coding agents out of the box, the pattern bakes the following flags into `start-vllm.sh` based on the selected model:

| Model family | Tool-call parser | `--max-model-len` |
|---|---|---|
| `Qwen/*`, `nvidia/OpenReasoning-Nemotron-*` | `hermes` | 32768 |
| `microsoft/Phi-4-mini-*` | `phi4_mini_json` | 32768 |
| `openai/gpt-oss-*` | `gpt_oss` | 32768 |
| `microsoft/phi-4` | (none) | 16384 |
| `zai-org/GLM-4-9B-0414` | (none — no validated 0414 parser) | 32768 |

All models also get `--kv-cache-dtype fp8` so the agent's tool-definition system prompt (typically 10–15K tokens) fits alongside a usable output budget on a 24 GB GPU.

If you set `CustomVllmConfigParameterArn`, your value is **appended** to the command, so any flag you provide overrides the baked-in default.

### Creating Configuration Parameters

Create SSM Parameter Store SecureString parameters containing your custom configuration:

```bash
# Custom vLLM configuration (e.g. raise context to 64K on a larger instance)
aws ssm put-parameter \
  --name "/oe-patterns/open-webui/${USER}/vllm-config" \
  --type "SecureString" \
  --value "--max-model-len 65536 --max-num-seqs 256"

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

2. **Secret Generation**: The CDK `Secret` construct's `generate_string_key` template generates `WEBUI_SECRET_KEY` (a secure 64-char string) at stack-create time. This was previously done via a `check-secrets.py` boot script; that script was removed in 1.0.1 in favor of the construct.

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
