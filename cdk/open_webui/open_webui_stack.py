import os
import subprocess
from aws_cdk import (
    Aws,
    CfnCondition,
    CfnOutput,
    CfnParameter,
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

AMI_ID="ami-0ab715b1314a24cd6" # ordinary-experts-patterns-open-webui-f0db43f-20250615-0346

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
                "Qwen/Qwen2.5-Coder-7B-Instruct"
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
                "g6e.xlarge",
                "g6e.2xlarge",
                "g6e.4xlarge",
                "g6e.8xlarge",
                "g6e.16xlarge"
            ],
            ami_id=AMI_ID,
            create_and_update_timeout_minutes = 60,
            default_instance_type = "g6e.xlarge",
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
        
        CfnOutput(
            self,
            "FirstUseInstructions",
            description="Instructions for getting started",
            value="TODO"
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
