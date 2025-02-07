import aws_cdk as core
import aws_cdk.assertions as assertions

from openwebui.openwebui_stack import OpenwebuiStack

# example tests. To run these tests, uncomment this file along with the example
# resource in openwebui/openwebui_stack.py
def test_sqs_queue_created():
    app = core.App()
    stack = OpenwebuiStack(app, "openwebui")
    template = assertions.Template.from_stack(stack)

#     template.has_resource_properties("AWS::SQS::Queue", {
#         "VisibilityTimeout": 300
#     })
