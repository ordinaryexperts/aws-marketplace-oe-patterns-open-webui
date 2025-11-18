.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  update-common           - Download common.mk from utilities repository"
	@echo "  test-integration-models - Run integration tests for model compatibility"
	@echo "  deploy                  - Deploy the CDK stack to AWS"
	@echo ""
	@echo "Targets from common.mk:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' common.mk 2>/dev/null | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-23s - %s\n", $$1, $$2}' || echo "  (run 'make update-common' first to see common targets)"

-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.7.1/common.mk

# Open WebUI specific integration test target for model testing
test-integration-models: build
	docker compose run -w /code/test/integration --rm devenv pytest test_models.py -v

deploy: build
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=76.88.34.94/32 \
	--parameters AsgAmiId=ami-062f8c7b5f728bb10 \
	--parameters AsgReprovisionString=20251116.13 \
	--parameters AsgInstanceType=g6.xlarge \
	--parameters Model=Qwen/Qwen2.5-Coder-7B-Instruct \
	--parameters DnsHostname=open-webui-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com
