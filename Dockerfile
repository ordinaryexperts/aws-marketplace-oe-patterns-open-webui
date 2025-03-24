FROM ordinaryexperts/aws-marketplace-patterns-devenv:2.4.1
# FROM devenv:latest

# install dependencies
RUN mkdir -p /tmp/code/cdk/open-webui
COPY ./cdk/requirements.txt /tmp/code/cdk/
RUN touch /tmp/code/cdk/README.md
WORKDIR /tmp/code/cdk
RUN pip3 install -r requirements.txt
RUN rm -rf /tmp/code
