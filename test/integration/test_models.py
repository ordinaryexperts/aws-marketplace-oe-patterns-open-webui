"""
Model functionality and aider compatibility tests for Open WebUI.
These tests validate model loading, inference, and aider integration.
"""

import pytest
import requests
import json
import time
from openai import OpenAI


class TestModelInference:
    """Test model loading and basic inference capabilities."""

    def test_model_loaded(self, base_url, api_base_path, api_key, config):
        """Verify a model is loaded via Open WebUI API."""
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)

        assert response.status_code == 200, \
            f"Failed to get models: {response.status_code}"

        data = response.json()
        assert "data" in data, "Response missing 'data' field"
        assert len(data["data"]) > 0, "No models loaded"

        # Store model info for other tests
        model_info = data["data"][0]
        print(f"\nLoaded model: {model_info['id']}")

    def test_basic_completion(self, base_url, api_base_path, api_key, config):
        """Test basic text completion through Open WebUI API."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        # Create OpenAI client pointing to Open WebUI
        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # Test simple completion
        completion = client.chat.completions.create(
            model=model_id,
            messages=[
                {"role": "user", "content": "Say 'hello' and nothing else."}
            ],
            max_tokens=50,
            temperature=0.1
        )

        assert completion.choices, "No completion choices returned"
        response_text = completion.choices[0].message.content
        assert response_text, "Empty response from model"
        assert "hello" in response_text.lower(), \
            f"Expected 'hello' in response, got: {response_text}"

    def test_streaming_completion(self, base_url, api_base_path, api_key, config):
        """Test streaming completion support."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        # Create OpenAI client
        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # Test streaming
        chunks = []
        stream = client.chat.completions.create(
            model=model_id,
            messages=[
                {"role": "user", "content": "Count from 1 to 3."}
            ],
            max_tokens=50,
            temperature=0.1,
            stream=True
        )

        for chunk in stream:
            if chunk.choices[0].delta.content:
                chunks.append(chunk.choices[0].delta.content)

        assert len(chunks) > 0, "No streaming chunks received"
        full_response = "".join(chunks)
        assert full_response, "Empty streaming response"


class TestAiderCompatibility:
    """Test aider AI coding assistant compatibility.

    Aider requires:
    - OpenAI-compatible API endpoint
    - Chat completions support
    - Streaming support
    - Function calling support (optional but recommended)
    """

    def test_openai_api_compatibility(self, base_url, api_base_path, api_key, config):
        """Test OpenAI API compatibility (required for aider)."""
        # Test /api/models endpoint
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)

        assert response.status_code == 200, \
            "OpenAI-compatible /api/models endpoint not accessible"

        data = response.json()
        assert "data" in data, "Response missing 'data' field"
        assert len(data["data"]) > 0, "No models available"

    def test_chat_completions_endpoint(self, base_url, api_base_path, api_key, config):
        """Test /api/chat/completions endpoint (required for aider)."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        # Test chat completions endpoint
        chat_url = f"{base_url}{api_base_path}/chat/completions"
        payload = {
            "model": model_id,
            "messages": [
                {"role": "user", "content": "Respond with OK"}
            ],
            "max_tokens": 20,
            "temperature": 0.1
        }

        response = requests.post(
            chat_url,
            headers=headers,
            json=payload,
            timeout=30
        )
        assert response.status_code == 200, \
            f"Chat completions endpoint failed: {response.status_code}"

        data = response.json()
        assert "choices" in data, "Response missing 'choices' field"
        assert len(data["choices"]) > 0, "No completion choices"

    def test_aider_coding_task(self, base_url, api_base_path, api_key, config):
        """Test aider-style coding task."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # Simulate aider coding request
        aider_prompt = config["aider"]["test_prompt"]
        completion = client.chat.completions.create(
            model=model_id,
            messages=[
                {
                    "role": "system",
                    "content": "You are a helpful coding assistant. Provide concise, working code."
                },
                {"role": "user", "content": aider_prompt}
            ],
            max_tokens=200,
            temperature=0.1
        )

        response_text = completion.choices[0].message.content
        assert response_text, "Empty response from model"

        # Check for expected code elements
        keywords = config["aider"]["expected_response_keywords"]
        found_keywords = [kw for kw in keywords if kw in response_text.lower()]
        assert len(found_keywords) >= 2, \
            f"Expected at least 2 of {keywords} in response, found: {found_keywords}\nResponse: {response_text}"

    def test_aider_edit_format(self, base_url, api_base_path, api_key, config):
        """Test aider's edit format handling."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # Test editing existing code
        edit_prompt = """Here is some code:

```python
def add(a, b):
    return a + b
```

Modify this function to add a docstring."""

        completion = client.chat.completions.create(
            model=model_id,
            messages=[
                {
                    "role": "system",
                    "content": "You are a code editor. Show the modified code."
                },
                {"role": "user", "content": edit_prompt}
            ],
            max_tokens=300,
            temperature=0.1
        )

        response_text = completion.choices[0].message.content
        assert response_text, "Empty response"
        assert "def add" in response_text, "Function definition should be present"
        # Check for docstring indicators
        assert '"""' in response_text or "'''" in response_text or "docstring" in response_text.lower(), \
            f"Expected docstring in response: {response_text}"

    def test_performance_for_aider(self, base_url, api_base_path, api_key, config):
        """Test that model responds fast enough for interactive aider use."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # Time a simple request
        start = time.time()
        completion = client.chat.completions.create(
            model=model_id,
            messages=[
                {"role": "user", "content": "Say OK"}
            ],
            max_tokens=10,
            temperature=0.1
        )
        elapsed = time.time() - start

        assert completion.choices[0].message.content, "Got response"

        # Aider should be usable if simple requests complete in < 10 seconds
        # For first token, < 30 seconds is acceptable
        assert elapsed < 30.0, \
            f"Response too slow for interactive use: {elapsed:.2f}s"

        print(f"\nModel response time: {elapsed:.2f}s")


class TestModelCapabilities:
    """Test specific model capabilities useful for coding."""

    def test_code_understanding(self, base_url, api_base_path, api_key):
        """Test model's code understanding."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        code_question = """What does this Python code do?

```python
result = [x**2 for x in range(5)]
```

Answer in one sentence."""

        completion = client.chat.completions.create(
            model=model_id,
            messages=[
                {"role": "user", "content": code_question}
            ],
            max_tokens=100,
            temperature=0.1
        )

        response_text = completion.choices[0].message.content.lower()
        # Should mention squares or squaring
        assert "square" in response_text or "power" in response_text or "**2" in response_text, \
            f"Model should understand code: {response_text}"

    def test_multi_turn_conversation(self, base_url, api_base_path, api_key):
        """Test multi-turn conversation (important for aider's iterative workflow)."""
        # Get loaded model
        models_url = f"{base_url}{api_base_path}/models"
        headers = {"Authorization": f"Bearer {api_key}"}
        response = requests.get(models_url, headers=headers, timeout=10)
        model_id = response.json()["data"][0]["id"]

        client = OpenAI(
            base_url=f"{base_url}{api_base_path}",
            api_key=api_key
        )

        # First message
        messages = [
            {"role": "user", "content": "Write a function called 'double' that doubles a number."}
        ]

        completion1 = client.chat.completions.create(
            model=model_id,
            messages=messages,
            max_tokens=150,
            temperature=0.1
        )

        response1 = completion1.choices[0].message.content
        assert "def" in response1 and "double" in response1, \
            f"First response should contain function: {response1}"

        # Follow-up message
        messages.append({"role": "assistant", "content": response1})
        messages.append({"role": "user", "content": "Now add a docstring to it."})

        completion2 = client.chat.completions.create(
            model=model_id,
            messages=messages,
            max_tokens=200,
            temperature=0.1
        )

        response2 = completion2.choices[0].message.content
        # Should reference the previous function
        assert "double" in response2.lower(), \
            f"Second response should reference the function: {response2}"
