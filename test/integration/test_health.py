"""
Health and basic connectivity tests for Open WebUI and vLLM.
These tests validate infrastructure and basic application health.
"""

import pytest
import requests
import json


class TestOpenWebUIHealth:
    """Level 1: Infrastructure and basic health tests."""

    def test_https_accessible(self, base_url):
        """Test that Open WebUI is accessible over HTTPS."""
        response = requests.get(base_url, timeout=30, allow_redirects=True)
        assert response.status_code == 200, \
            f"Failed to access Open WebUI at {base_url}"
        assert response.url.startswith("https://"), \
            "Open WebUI should be accessible via HTTPS"

    def test_health_endpoint(self, base_url, config):
        """Test Open WebUI health check endpoint."""
        health_url = f"{base_url}{config['application']['health_endpoint']}"
        response = requests.get(health_url, timeout=10)

        assert response.status_code == 200, \
            f"Health check failed with status {response.status_code}"

        # Open WebUI's health endpoint returns JSON
        data = response.json()
        expected = config['application']['health_expected_response']
        assert data.get("status") == expected or data == expected, \
            f"Health check returned unexpected status: {data}"

    def test_vllm_health_endpoint(self, base_url, config):
        """Test vLLM health check endpoint."""
        vllm_url = f"{base_url}{config['application']['vllm_health_endpoint']}"
        response = requests.get(vllm_url, timeout=10)

        assert response.status_code == 200, \
            f"vLLM health check failed with status {response.status_code}"

    def test_vllm_models_endpoint(self, base_url, config):
        """Test vLLM models endpoint to verify model is loaded."""
        models_url = f"{base_url}{config['application']['vllm_models_endpoint']}"
        response = requests.get(models_url, timeout=10)

        assert response.status_code == 200, \
            f"vLLM models endpoint failed with status {response.status_code}"

        data = response.json()
        assert "data" in data, "Models response missing 'data' field"
        assert len(data["data"]) > 0, "No models loaded in vLLM"

        # Verify model has required fields
        model = data["data"][0]
        assert "id" in model, "Model missing 'id' field"
        assert "object" in model, "Model missing 'object' field"

    def test_response_time(self, base_url, config):
        """Test that Open WebUI responds within acceptable time."""
        import time

        health_url = f"{base_url}{config['application']['health_endpoint']}"
        start = time.time()
        response = requests.get(health_url, timeout=30)
        elapsed = time.time() - start

        assert response.status_code == 200, \
            "Health check failed"
        assert elapsed < 5.0, \
            f"Response time {elapsed:.2f}s exceeds 5 seconds"

    def test_ssl_certificate(self, base_url):
        """Verify SSL certificate is valid."""
        import ssl
        import socket
        from urllib.parse import urlparse

        parsed = urlparse(base_url)
        hostname = parsed.hostname
        port = parsed.port or 443

        context = ssl.create_default_context()
        try:
            with socket.create_connection((hostname, port), timeout=10) as sock:
                with context.wrap_socket(sock, server_hostname=hostname) as ssock:
                    cert = ssock.getpeercert()
                    assert cert is not None, "No SSL certificate found"

                    # Certificate is valid if we get here without exception
        except ssl.SSLError as e:
            pytest.fail(f"SSL certificate validation failed: {e}")

    def test_security_headers(self, base_url):
        """Test that important security headers are present."""
        response = requests.get(base_url, timeout=10)
        headers = response.headers

        # Basic security headers
        assert "X-Content-Type-Options" in headers, \
            "X-Content-Type-Options header missing"


class TestOpenWebUIInfrastructure:
    """Level 2: AWS infrastructure tests."""

    def test_cloudformation_stack_exists(self, cloudformation_client, stack_name):
        """Verify CloudFormation stack exists and is in good state."""
        response = cloudformation_client.describe_stacks(StackName=stack_name)

        assert len(response["Stacks"]) == 1, \
            f"Expected 1 stack, found {len(response['Stacks'])}"

        stack = response["Stacks"][0]
        assert stack["StackStatus"] in ["CREATE_COMPLETE", "UPDATE_COMPLETE"], \
            f"Stack is in unexpected state: {stack['StackStatus']}"

    def test_stack_outputs(self, stack_outputs):
        """Verify CloudFormation stack has required outputs."""
        required_outputs = [
            "DnsSiteUrlOutput",
            "VpcIdOutput",
        ]

        for output in required_outputs:
            assert output in stack_outputs, \
                f"Required output '{output}' missing from stack"
            assert stack_outputs[output], \
                f"Output '{output}' is empty"

    def test_ec2_instance_running(self, instance_id, ec2_client):
        """Verify EC2 instance is running."""
        response = ec2_client.describe_instances(InstanceIds=[instance_id])

        assert len(response["Reservations"]) > 0, \
            f"No reservations found for instance {instance_id}"

        instance = response["Reservations"][0]["Instances"][0]
        assert instance["State"]["Name"] == "running", \
            f"Instance is not running: {instance['State']['Name']}"

    def test_instance_has_gpu(self, instance_id, ec2_client):
        """Verify instance has GPU (g6e instance type)."""
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response["Reservations"][0]["Instances"][0]

        instance_type = instance["InstanceType"]
        assert instance_type.startswith("g6e."), \
            f"Instance should be g6e type, got: {instance_type}"

    def test_instance_has_data_volume(self, instance_id, ec2_client):
        """Verify instance has data volume attached."""
        response = ec2_client.describe_instances(InstanceIds=[instance_id])
        instance = response["Reservations"][0]["Instances"][0]

        block_devices = instance.get("BlockDeviceMappings", [])
        # Should have root volume + data volume
        assert len(block_devices) >= 2, \
            f"Expected at least 2 volumes (root + data), found {len(block_devices)}"
