import os
import subprocess
from aws_cdk import (
    Aws,
    CfnCondition,
    CfnOutput,
    CfnParameter,
    CfnRule,
    Fn,
    Stack,
    Token
)
from constructs import Construct

from oe_patterns_cdk_common.alb import Alb
from oe_patterns_cdk_common.asg import Asg
from oe_patterns_cdk_common.dns import Dns
from oe_patterns_cdk_common.vpc import Vpc

if 'TEMPLATE_VERSION' in os.environ:
    template_version = os.environ['TEMPLATE_VERSION']
else:
    try:
        template_version = subprocess.check_output(["git", "describe", "--always"]).strip().decode('ascii')
    except:
        template_version = "CICD"

AMI_ID="ami-062f8c7b5f728bb10" # ordinary-experts-patterns-open-webui-ac9f890-nvme-direct-download-20251116-0736 (Ubuntu 24.04 + Python 3.12 venv, model downloads directly to NVMe on boot)

class OpenWebuiStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.custom_open_webui_config_parameter_arn_param = CfnParameter(
            self,
            "CustomOpenWebuiConfigParameterArn",
            default="",
            description="Optional: ARN of SSM Parameter Store Secure String containing custom config for Open WebUI."
        )

        self.custom_vllm_config_parameter_arn_param = CfnParameter(
            self,
            "CustomVllmConfigParameterArn",
            default="",
            description="Optional: ARN of SSM Parameter Store Secure String containing custom config for VLLM."
        )

        self.model_param = CfnParameter(
            self,
            "Model",
            default="Qwen/Qwen2.5-Coder-7B-Instruct",
            allowed_values=[
                "microsoft/phi-4",
                "microsoft/Phi-4-mini-reasoning",
                "nvidia/OpenReasoning-Nemotron-7B",
                "nvidia/OpenReasoning-Nemotron-14B",
                "nvidia/OpenReasoning-Nemotron-32B",
                "Qwen/Qwen2.5-Coder-7B-Instruct",
                "Qwen/Qwen2.5-Coder-14B-Instruct",
                "Qwen/Qwen2.5-Coder-32B-Instruct"
            ],
            description="The LLM to load. These models have been tested with this configuration. To try a different model, see the ModelOverride parameter"
        )

        self.model_override_param = CfnParameter(
            self,
            "ModelOverride",
            default="",
            description="Enter a model name here, in Hugging Face format, i.e. <orgname>/<modelname>, to override the default list. See /var/log/vllm.log (on the instance or in CloudWatch Logs) for troubleshooting new models."
        )

        self.model_override_exists_condition = CfnCondition(
            self,
            "ModelOverrideExists",
            expression=Fn.condition_not(Fn.condition_equals(self.model_override_param.value, ""))
        )

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        dns = Dns(self, "Dns")

        with open("open_webui/user_data.sh") as f:
            user_data = f.read()
        asg = Asg(
            self,
            "Asg",
            allowed_instance_types = [
                "g6.xlarge",
                "g6.2xlarge",
                "g6.4xlarge",
                "g6.8xlarge",
                "g6.16xlarge",
                "g6e.xlarge",
                "g6e.2xlarge",
                "g6e.4xlarge",
                "g6e.8xlarge",
                "g6e.16xlarge"
            ],
            ami_id=AMI_ID,
            create_and_update_timeout_minutes = 60,  # 1 hour - vLLM model download and load typically takes 10-15 minutes on NVMe
            default_instance_type = "g6.xlarge",
            singleton = True,
            use_data_volume = True,
            user_data_contents = user_data,
            user_data_variables={
                "CustomOpenWebuiConfigParameterArn": self.custom_vllm_config_parameter_arn_param.value_as_string,
                "CustomVllmConfigParameterArn": self.custom_open_webui_config_parameter_arn_param.value_as_string,
                "HostedZoneName": dns.route_53_hosted_zone_name_param.value_as_string,
                "Hostname": dns.hostname(),
                "InstanceSecretName": Aws.STACK_NAME + "/instance/credentials",
                "ModelName": Token.as_string(
                    Fn.condition_if(
                        self.model_override_exists_condition.logical_id,
                        self.model_override_param.value_as_string,
                        self.model_param.value_as_string
                    )
                )
            },
            vpc = vpc
        )

        alb = Alb(
            self,
            "Alb",
            asg=asg,
            health_check_path = "/elb-check",
            vpc=vpc
        )
        asg.asg.target_group_arns = [ alb.target_group.ref ]

        dns.add_alb(alb)

        # CloudFormation Rules for fail-fast validation of model/instance compatibility
        # Rule 1: Prevent 14B+ models on instances with < 48GB VRAM (only g6.xlarge with 24GB)
        # Note: g6e.xlarge has 48GB VRAM and works with 14B models
        # Tested: phi-4 and Qwen 14B both fail on g6.xlarge (24GB VRAM)
        CfnRule(
            self,
            "Model14BRequiresLargerInstance",
            assertions=[
                {
                    "assert": Fn.condition_or(
                        # Allow if NOT using a 14B/32B model...
                        Fn.condition_not(
                            Fn.condition_or(
                                Fn.condition_equals(self.model_param.value_as_string, "microsoft/phi-4"),
                                Fn.condition_equals(self.model_param.value_as_string, "nvidia/OpenReasoning-Nemotron-14B"),
                                Fn.condition_equals(self.model_param.value_as_string, "nvidia/OpenReasoning-Nemotron-32B"),
                                Fn.condition_equals(self.model_param.value_as_string, "Qwen/Qwen2.5-Coder-14B-Instruct"),
                                Fn.condition_equals(self.model_param.value_as_string, "Qwen/Qwen2.5-Coder-32B-Instruct")
                            )
                        ),
                        # OR allow if instance is NOT g6.xlarge (g6.xlarge has only 24GB VRAM)
                        Fn.condition_not(
                            Fn.condition_equals(asg.instance_type_param.value_as_string, "g6.xlarge")
                        )
                    ),
                    "assertDescription": "14B and 32B models require at least 48GB VRAM. The g6.xlarge instance only has 24GB VRAM. Please select g6e.xlarge (48GB) or larger: g6.2xlarge, g6.4xlarge, g6.8xlarge, g6.16xlarge, g6e.2xlarge, g6e.4xlarge, g6e.8xlarge, or g6e.16xlarge."
                }
            ]
        )

        CfnOutput(
            self,
            "FirstUseInstructions",
            description="Instructions for getting started",
            value=Fn.sub(
                "Stack deployment complete! Access Open WebUI at https://${Hostname}. "
                "Initial setup: 1) Create admin account at first login. "
                "2) Navigate to Settings > Account to create an API key for aider/external tools. "
                "Instance type: ${InstanceType}, Model: ${ModelName}. "
                "For troubleshooting, check CloudWatch Logs or /var/log/vllm.log on the EC2 instance.",
                {
                    "Hostname": dns.hostname(),
                    "InstanceType": asg.instance_type_param.value_as_string,
                    "ModelName": Token.as_string(
                        Fn.condition_if(
                            self.model_override_exists_condition.logical_id,
                            self.model_override_param.value_as_string,
                            self.model_param.value_as_string
                        )
                    )
                }
            )
        )

        parameter_groups = [
            {
                "Label": {
                    "default": "Application Config"
                },
                "Parameters": [
                    self.model_param.logical_id,
                    self.model_override_param.logical_id
                ]
            }
        ]
        parameter_groups += alb.metadata_parameter_group()
        parameter_groups += asg.metadata_parameter_group()
        parameter_groups += dns.metadata_parameter_group()
        parameter_groups += vpc.metadata_parameter_group()

        # AWS::CloudFormation::Interface
        self.template_options.metadata = {
            "OE::Patterns::TemplateVersion": template_version,
            "AWS::CloudFormation::Interface": {
                "ParameterGroups": parameter_groups,
                "ParameterLabels": {
                    self.model_param.logical_id: {
                        "default": "Model"
                    },
                    self.model_override_param.logical_id: {
                        "default": "Model Override"
                    },
                    **alb.metadata_parameter_labels(),
                    **asg.metadata_parameter_labels(),
                    **dns.metadata_parameter_labels(),
                    **vpc.metadata_parameter_labels()
                }
            }
        }
