.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  update-common           - Download common.mk from utilities repository"
	@echo "  clean-cdk               - Clean CDK output directory (fixes permission issues)"
	@echo "  test-integration-models - Run integration tests for model compatibility"
	@echo "  deploy                  - Deploy the CDK stack to AWS"
	@echo ""
	@echo "AWS Marketplace targets (from common.mk):"
	@echo "  marketplace-validate    - Check product is ready for version submission"
	@echo "  marketplace-submit      - Submit a new version (AMI_ID=xxx TEMPLATE_VERSION=x.y.z)"
	@echo "  marketplace-status      - Check submission status"
	@echo ""
	@echo "Targets from common.mk:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' common.mk 2>/dev/null | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-23s - %s\n", $$1, $$2}' || echo "  (run 'make update-common' first to see common targets)"

-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/main/common.mk

# Open WebUI specific integration test target for model testing
test-integration-models: build
	docker compose run -w /code/test/integration --rm devenv pytest test_models.py -v

deploy: build clean-cdk
	docker compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=0.0.0.0/0 \
	--parameters AsgAmiIdv110=ami-0665ec9b6b44a0364 \
	--parameters AsgReprovisionString=20260502.2 \
	--parameters AsgInstanceType=g6.xlarge \
	--parameters Model=Qwen/Qwen3-8B \
	--parameters DnsHostname=open-webui-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters CustomVllmConfigParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns/open-webui/${USER}/vllm-config \
	--parameters CustomOpenWebuiConfigParameterArn=arn:aws:ssm:us-east-1:992593896645:parameter/oe-patterns/open-webui/${USER}/openwebui-config
