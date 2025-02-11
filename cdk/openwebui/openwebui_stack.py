import os
import subprocess
from aws_cdk import (
    Aws,
    CfnMapping,
    CfnOutput,
    Stack
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

AMI_ID="ami-0077611e201e19f5f"
AMI_NAME="ordinary-experts-patterns-openwebui-21fd255-20250208-0559"
generated_ami_ids = {
    "us-east-1": "ami-0077611e201e19f5f"
}
# End generated code block.

class OpenwebuiStack(Stack):

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # vpc
        vpc = Vpc(
            self,
            "Vpc"
        )

        dns = Dns(self, "Dns")

        with open("openwebui/user_data.sh") as f:
            user_data = f.read()
        asg = Asg(
            self,
            "Asg",
            allowed_instance_types = [
                "g6e.xlarge",
                "g6e.2xlarge",
                "g6e.4xlarge",
                "g6e.8xlarge",
                "g6e.16xlarge",
                "g6e.12xlarge",
                "g6e.24xlarge",
                "g6e.48xlarge"
            ],
            default_instance_type = "g6e.xlarge",
            singleton = True,
            use_data_volume = True,
            user_data_contents = user_data,
            user_data_variables={
                "Hostname": dns.hostname(),
                "HostedZoneName": dns.route_53_hosted_zone_name_param.value_as_string,
                "InstanceSecretName": Aws.STACK_NAME + "/instance/credentials"
            },
            vpc = vpc
        )
        ami_mapping={
            "AMI": {
                "OEOPENWEBUI": AMI_NAME
            }
        }
        for region in generated_ami_ids.keys():
            ami_mapping[region] = { "AMI": generated_ami_ids[region] }
        CfnMapping(
            self,
            "AWSAMIRegionMap",
            mapping=ami_mapping
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

        parameter_groups = []
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
                    **alb.metadata_parameter_labels(),
                    **asg.metadata_parameter_labels(),
                    **dns.metadata_parameter_labels(),
                    **vpc.metadata_parameter_labels()
                }
            }
        }
