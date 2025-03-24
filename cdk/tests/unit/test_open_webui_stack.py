import aws_cdk as core
import aws_cdk.assertions as assertions

from open_webui.open_webui_stack import OpenWebuiStack

# example tests. To run these tests, uncomment this file along with the example
# resource in openwebui/openwebui_stack.py
def test_sqs_queue_created():
    app = core.App()
    stack = OpenWebuiStack(app, "open-webui")
    template = assertions.Template.from_stack(stack)
