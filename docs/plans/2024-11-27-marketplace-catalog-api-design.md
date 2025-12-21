# AWS Marketplace Catalog API Release Automation

## Overview

Automate AMI version submission and status monitoring for AWS Marketplace releases using the Catalog API. This replaces the deprecated PLF (Product Load Form) Excel workflow.

## Problem

The old release workflow required:
1. Downloading PLF Excel file from portal
2. Running `make plf` to populate pricing across all instance types/regions
3. Manually uploading Excel to AWS Management Portal
4. Manual AMI sharing for scanning

AWS has deprecated the PLF workflow. The Catalog API provides programmatic access to submit versions directly.

## Solution

A Python script with three commands:
- `validate` - Check product exists and has required metadata
- `submit` - Submit a new AMI version with CloudFormation template
- `status` - Check submission status

## Files

```
aws-marketplace-oe-patterns-open-webui/
├── marketplace_config.yaml      # Static product configuration
├── scripts/
│   └── marketplace.py           # Main script
└── Makefile                     # New targets
```

## Configuration

**`marketplace_config.yaml`:**

```yaml
# AWS Marketplace Product Configuration
product_id: ""  # Fill after creating product in portal
ami_access_role_arn: "arn:aws:iam::ACCOUNT_ID:role/AwsMarketplaceAmiIngestion"

# Template publishing
template_bucket: "ordinary-experts-aws-marketplace-pattern-artifacts"
template_pattern: "open_webui"

# AMI metadata
operating_system: "UBUNTU"
operating_system_version: "24.04"
username: "ubuntu"

# CloudFormation parameter pattern (version 1.0.0 -> AsgAmiIdv100)
ami_parameter_pattern: "AsgAmiIdv{version}"

# CloudFormation delivery option details
architecture_diagram_url: ""  # URL to architecture diagram image
aws_calculator_url: ""        # AWS Pricing Calculator estimate URL
```

## Makefile Targets

```makefile
marketplace-validate:
	docker compose run -w /code --rm devenv python scripts/marketplace.py validate

marketplace-submit:
	docker compose run -w /code --rm devenv python scripts/marketplace.py submit \
		--ami-id $(AMI_ID) \
		--version $(TEMPLATE_VERSION)

marketplace-status:
	docker compose run -w /code --rm devenv python scripts/marketplace.py status
```

## Script Commands

### `validate`

Checks that the product is ready for version submission:

1. Reads `product_id` from config
2. Calls `DescribeEntity` to fetch product details
3. Validates required fields:
   - Title
   - Short description
   - Long description
   - Logo URL
   - At least one highlight
   - Support information
   - EULA
4. Reports missing fields or confirms ready

**Example output:**
```
Validating product prod-abc123...

✓ Title: "Ordinary Experts Open WebUI Pattern"
✓ Short description: set (156 chars)
✓ Long description: set (892 chars)
✓ Logo URL: set
✗ Highlights: missing (need at least 1)
✓ Support information: set
✓ EULA: set

Product is NOT ready for version submission.
Missing: Highlights
```

### `submit`

Submits a new AMI version:

1. Validates config file is complete
2. Runs `cdk synth` and verifies versioned AMI parameter exists (e.g., `AsgAmiIdv100`)
3. Publishes template to S3 via existing `publish-template.sh`
4. Parses release notes from `CHANGELOG.md` (looks for `## {version}` section)
5. Calls `StartChangeSet` with `AddDeliveryOptions`:
   - Version title and release notes
   - AMI source with access role ARN
   - CloudFormation template URL
   - Architecture diagram and calculator URLs
6. Saves changeset ID to `.marketplace_changeset` file
7. Prints changeset ID for tracking

**Example:**
```
$ make marketplace-submit AMI_ID=ami-0123456789 TEMPLATE_VERSION=1.0.0

Validating configuration...
✓ Config file loaded
✓ Product ID: prod-abc123
✓ AMI access role ARN configured

Validating CloudFormation template...
✓ Parameter AsgAmiIdv100 found in template

Publishing template to S3...
✓ Uploaded to s3://ordinary-experts-aws-marketplace-pattern-artifacts/open_webui/1.0.0/template.yaml

Parsing release notes from CHANGELOG.md...
✓ Found release notes for version 1.0.0

Submitting version to AWS Marketplace...
✓ Change set created: cs-abc123xyz

Change set ID saved to .marketplace_changeset
Check status with: make marketplace-status
```

### `status`

Checks submission status:

1. Reads changeset ID from `.marketplace_changeset` (or accepts `CHANGESET_ID` argument)
2. Calls `DescribeChangeSet`
3. Reports status: PREPARING, APPLYING, SUCCEEDED, FAILED
4. If failed, shows error details

**Example:**
```
$ make marketplace-status

Change set: cs-abc123xyz
Status: APPLYING
Started: 2024-11-27 10:30:00

Version submission is in progress. This can take a few hours.
```

## CHANGELOG.md Format

The script parses release notes from CHANGELOG.md using standard Keep a Changelog format:

```markdown
# CHANGELOG

## 1.0.0

- Initial release
- GPU-accelerated LLM inference with vLLM
- Open WebUI interface

## Unreleased

- Future stuff
```

The script:
- Looks for `## {version}` heading
- Extracts content until next `##` heading or end of file
- Fails with clear error if version section not found

## IAM Role Setup

Create this role in your prod AWS account before using the Catalog API.

**Role name:** `AwsMarketplaceAmiIngestion`

**Trust policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "assets.marketplace.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:DescribeSnapshots",
        "ec2:ModifyImageAttribute",
        "ec2:ModifySnapshotAttribute"
      ],
      "Resource": "*"
    }
  ]
}
```

**AWS CLI commands to create:**
```bash
# Create the role
aws iam create-role \
  --role-name AwsMarketplaceAmiIngestion \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "assets.marketplace.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'

# Attach permissions
aws iam put-role-policy \
  --role-name AwsMarketplaceAmiIngestion \
  --policy-name AmiAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:ModifyImageAttribute",
          "ec2:ModifySnapshotAttribute"
        ],
        "Resource": "*"
      }
    ]
  }'
```

## Versioned AMI Parameters

CloudFormation parameter defaults don't update for existing stacks. To ensure customers get new AMIs on upgrade, each version uses a unique parameter name.

**Pattern:** `AsgAmiIdv{version}` where version `1.0.0` becomes `100`

**Example in CDK:**
```python
# Version 1.0.0
ami_id_param_v100 = CfnParameter(
    self, "AsgAmiIdv100",
    type="AWS::EC2::Image::Id",
    default="ami-0123456789abcdef0",
    description="AMI ID for version 1.0.0"
)
```

The script validates this parameter exists in the synthesized template before submitting.

## New Release Workflow

### One-time setup

1. Create `AwsMarketplaceAmiIngestion` IAM role in prod account (see above)
2. Create product in AWS Marketplace Management Portal
   - Fill in: title, descriptions, logo, highlights, support info, EULA, pricing ($0.02/hr flat)
3. Copy product ID to `marketplace_config.yaml`
4. Fill in `architecture_diagram_url` and `aws_calculator_url`
5. Run `make marketplace-validate` to confirm ready

### Per-release workflow

1. **Create release branch**
   ```bash
   git flow release start 1.0.0
   vim CHANGELOG.md  # Add release notes under ## 1.0.0
   git add CHANGELOG.md
   ```

2. **Build AMI in prod**
   ```bash
   export TEMPLATE_VERSION=1.0.0
   AWS_PROFILE=oe-patterns-prod make TEMPLATE_VERSION=$TEMPLATE_VERSION ami-ec2-build
   export AMI_ID=ami-xxx  # from build output
   ```

3. **Update CDK with versioned AMI parameter**
   ```bash
   vim cdk/open_webui/open_webui_stack.py  # Add AsgAmiIdv100 parameter
   make synth-to-file
   # Test manually in prod account
   git add cdk
   git commit -m "Updated AMI for $TEMPLATE_VERSION"
   ```

4. **Submit to AWS Marketplace**
   ```bash
   AWS_PROFILE=oe-patterns-prod make marketplace-submit AMI_ID=$AMI_ID TEMPLATE_VERSION=$TEMPLATE_VERSION
   ```

5. **Monitor status**
   ```bash
   AWS_PROFILE=oe-patterns-prod make marketplace-status
   ```

6. **Finish release** (after AWS approval)
   ```bash
   git flow release finish $TEMPLATE_VERSION
   git checkout main && git push && git push --tags
   git checkout develop && git push
   ```

## API Details

### AddDeliveryOptions Request

```json
{
  "Catalog": "AWSMarketplace",
  "ChangeSet": [
    {
      "ChangeType": "AddDeliveryOptions",
      "Entity": {
        "Type": "AmiProduct@1.0",
        "Identifier": "prod-abc123"
      },
      "DetailsDocument": {
        "Version": {
          "VersionTitle": "1.0.0",
          "ReleaseNotes": "- Initial release\n- GPU-accelerated LLM inference"
        },
        "DeliveryOptions": [
          {
            "Details": {
              "AmiDeliveryOptionDetails": {
                "AmiSource": {
                  "AmiId": "ami-0123456789abcdef0",
                  "AccessRoleArn": "arn:aws:iam::123456789012:role/AwsMarketplaceAmiIngestion",
                  "UserName": "ubuntu",
                  "OperatingSystemName": "UBUNTU",
                  "OperatingSystemVersion": "24.04"
                },
                "UsageInstructions": "See GitHub documentation",
                "RecommendedInstanceType": "g6e.xlarge",
                "SecurityGroups": [
                  {
                    "IpProtocol": "tcp",
                    "FromPort": 443,
                    "ToPort": 443,
                    "IpRanges": ["0.0.0.0/0"]
                  }
                ]
              }
            }
          },
          {
            "Details": {
              "CloudFormationDeliveryOptionDetails": {
                "TemplateUrl": "https://ordinary-experts-aws-marketplace-pattern-artifacts.s3.amazonaws.com/open_webui/1.0.0/template.yaml"
              }
            }
          }
        ]
      }
    }
  ]
}
```

## References

- [AWS Marketplace Catalog API - Work with AMI-based products](https://docs.aws.amazon.com/marketplace/latest/APIReference/work-with-single-ami-products.html)
- [AWS Blog - Automating updates to Single AMI listings](https://aws.amazon.com/blogs/awsmarketplace/automating-updates-to-your-single-ami-listings-in-aws-marketplace-with-catalog-api/)
- [AWS Marketplace Catalog API Python Shapes](https://github.com/awslabs/aws-marketplace-catalog-api-shapes-for-python)
