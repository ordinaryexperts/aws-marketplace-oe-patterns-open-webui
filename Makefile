-include common.mk

update-common:
	wget -O common.mk https://raw.githubusercontent.com/ordinaryexperts/aws-marketplace-utilities/1.6.1/common.mk

deploy: build
	docker-compose run -w /code/cdk --rm devenv cdk deploy \
	--require-approval never \
	--parameters AlbCertificateArn=arn:aws:acm:us-east-1:992593896645:certificate/943928d7-bfce-469c-b1bf-11561024580e \
	--parameters AlbIngressCidr=76.88.36.112/32 \
	--parameters AsgAmiId=ami-06b9e0fd198a2bc3e \
	--parameters AsgReprovisionString=20250321.1 \
	--parameters AsgInstanceType=g6e.xlarge \
	--parameters DnsHostname=open-webui-${USER}.dev.patterns.ordinaryexperts.com \
	--parameters DnsRoute53HostedZoneName=dev.patterns.ordinaryexperts.com \
	--parameters Model=Qwen/Qwen2.5-Coder-7B-Instruct
