# Unreleased

# 1.1.0

* Upgrading to Open WebUI 0.10.2 (from 0.6.36)
  * Includes Open WebUI 0.9.0 database schema migration (runs automatically on first boot; persistent /data volume preserved)
* Bumped CUDA toolkit and NVIDIA driver:
  * CUDA 12.8.1 -> 13.0.2
  * NVIDIA driver 570.124.06 -> 580.95.05
  * cuDNN 9.8.0 -> 9.13.0 (cudnn-cuda-13 meta-package)
  * Required for vLLM 0.20.0 (PyTorch built against newer CUDA)
* Pinned vLLM to 0.20.0 in packer install (was unpinned)
* Refreshed model dropdown:
  * Added: Qwen/Qwen3-Coder-30B-A3B-Instruct (Apache 2.0, MoE 30B/3B-active, replaces Qwen2.5-Coder-14B/32B)
  * Added: openai/gpt-oss-20b (Apache 2.0, general-purpose)
  * Added: zai-org/GLM-4-9B-0414 (MIT, 9B general-purpose, 32K context; verified loading on g6e.4xlarge). No validated vLLM tool-call parser for the GLM-4-0414 dense series yet, so it uses the default config (tool calling off, 32K max-model-len).
  * Removed: Qwen/Qwen2.5-Coder-14B-Instruct, Qwen/Qwen2.5-Coder-32B-Instruct, nvidia/OpenReasoning-Nemotron-7B, nvidia/OpenReasoning-Nemotron-14B
  * Replaced default: Qwen/Qwen2.5-Coder-7B-Instruct -> Qwen/Qwen3-8B (Qwen3 generation, better tool-calling support, fits g6.xlarge)
* Fixed Open WebUI custom config SSM lookup hanging in systemd context: added explicit --region and timeout 30 wrapper to aws ssm get-parameter call in start-open-webui.sh
* Added model-aware vLLM tool-calling parser defaults so OpenAI-compatible clients (opencode, aider, etc.) work out of the box:
  * Qwen / nvidia OpenReasoning Nemotron -> hermes parser
  * microsoft/Phi-4-mini-reasoning -> phi4_mini_json parser
  * openai/gpt-oss-* -> gpt_oss parser
  * Custom overrides via CustomVllmConfigParameterArn still take precedence
* Added default --max-model-len + --kv-cache-dtype fp8 in start-vllm.sh:
  * 32K context + FP8 KV cache for most models (16K for microsoft/phi-4 - that's its native limit)
  * Required for agentic clients whose tool-definition system prompts exceed 8-12K tokens
  * Fits comfortably on g6.xlarge / g6e.xlarge (24/48 GB VRAM) with FP8 quantization
* Refactored secret handling to use Secret construct's built-in WEBUI_SECRET_KEY generation (removed bespoke check-secrets.py)
* Updated oe-patterns-cdk-common to 4.5.1
* Bumped CloudFormation parameter name AsgAmiIdv101 -> AsgAmiIdv110
* Bumped devenv image to 2.8.6 (Node 22, EOL 2027-04-30)

# 1.0.0

* TaskCat tests
* Installing Open WebUI 0.6.36
* Installing vllm
* Initial development
