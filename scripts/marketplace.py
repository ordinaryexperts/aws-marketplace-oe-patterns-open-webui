#!/usr/bin/env python3
"""
AWS Marketplace Catalog API automation for version submission.

Commands:
  validate  - Check product exists and has required metadata
  submit    - Submit a new AMI version with CloudFormation template
  status    - Check submission status
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import boto3
import yaml


CONFIG_FILE = "marketplace_config.yaml"
CHANGESET_FILE = ".marketplace_changeset"
CATALOG_REGION = "us-east-1"  # Catalog API only available in us-east-1


def load_config():
    """Load and validate marketplace config file."""
    config_path = Path(CONFIG_FILE)
    if not config_path.exists():
        print(f"Error: {CONFIG_FILE} not found")
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    return config


def get_catalog_client():
    """Get boto3 client for Marketplace Catalog API."""
    return boto3.client("marketplace-catalog", region_name=CATALOG_REGION)


def version_to_param_suffix(version: str) -> str:
    """Convert version string to parameter suffix (1.0.0 -> 100)."""
    return version.replace(".", "")


def get_ami_parameter_name(config: dict, version: str) -> str:
    """Get the expected AMI parameter name for a version."""
    pattern = config.get("ami_parameter_pattern", "AsgAmiIdv{version}")
    suffix = version_to_param_suffix(version)
    return pattern.format(version=suffix)


# -----------------------------------------------------------------------------
# Validate command
# -----------------------------------------------------------------------------

def cmd_validate(args):
    """Validate product exists and has required metadata."""
    config = load_config()

    product_id = config.get("product_id", "").strip()
    if not product_id:
        print("Error: product_id not set in marketplace_config.yaml")
        print("Create your product in the AWS Marketplace Management Portal first,")
        print("then copy the Product ID to the config file.")
        sys.exit(1)

    print(f"Validating product {product_id}...")
    print()

    client = get_catalog_client()

    try:
        response = client.describe_entity(
            Catalog="AWSMarketplace",
            EntityId=product_id
        )
    except client.exceptions.ResourceNotFoundException:
        print(f"Error: Product {product_id} not found")
        print("Check the product_id in marketplace_config.yaml")
        sys.exit(1)
    except Exception as e:
        print(f"Error describing product: {e}")
        sys.exit(1)

    # Parse the entity details
    details = json.loads(response.get("Details", "{}"))

    # Check required fields
    required_fields = {
        "Title": details.get("Description", {}).get("ProductTitle"),
        "Short description": details.get("Description", {}).get("ShortDescription"),
        "Long description": details.get("Description", {}).get("LongDescription"),
        "Logo URL": details.get("Description", {}).get("LogoUrl"),
        "Highlights": details.get("Description", {}).get("Highlights", []),
        "Support description": details.get("SupportInformation", {}).get("Description"),
    }

    all_valid = True
    for field, value in required_fields.items():
        if field == "Highlights":
            if value and len(value) > 0:
                print(f"  ✓ {field}: {len(value)} highlight(s)")
            else:
                print(f"  ✗ {field}: missing (need at least 1)")
                all_valid = False
        elif value:
            display = value[:50] + "..." if len(str(value)) > 50 else value
            print(f"  ✓ {field}: {display}")
        else:
            print(f"  ✗ {field}: missing")
            all_valid = False

    print()
    if all_valid:
        print("Product is ready for version submission.")
        return 0
    else:
        print("Product is NOT ready for version submission.")
        print("Fill in missing fields in the AWS Marketplace Management Portal.")
        return 1


# -----------------------------------------------------------------------------
# Submit command
# -----------------------------------------------------------------------------

def parse_changelog(version: str) -> str:
    """Extract release notes for a version from CHANGELOG.md."""
    changelog_path = Path("CHANGELOG.md")
    if not changelog_path.exists():
        print("Error: CHANGELOG.md not found")
        sys.exit(1)

    content = changelog_path.read_text()

    # Look for ## {version} section
    pattern = rf"^## {re.escape(version)}\s*$"
    match = re.search(pattern, content, re.MULTILINE)

    if not match:
        print(f"Error: Version {version} not found in CHANGELOG.md")
        print(f"Add a '## {version}' section with release notes.")
        sys.exit(1)

    # Extract content until next ## or end of file
    start = match.end()
    next_section = re.search(r"^## ", content[start:], re.MULTILINE)

    if next_section:
        end = start + next_section.start()
    else:
        end = len(content)

    release_notes = content[start:end].strip()

    if not release_notes:
        print(f"Error: Release notes for version {version} are empty")
        sys.exit(1)

    return release_notes


def validate_template_parameter(config: dict, version: str) -> bool:
    """Check that the versioned AMI parameter exists in the CloudFormation template."""
    param_name = get_ami_parameter_name(config, version)

    # Synth the template
    print("Synthesizing CloudFormation template...")
    result = subprocess.run(
        ["make", "synth-to-file"],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"Error: Failed to synthesize template")
        print(result.stderr)
        sys.exit(1)

    # Check the template for the parameter
    template_path = Path("dist/template.yaml")
    if not template_path.exists():
        print("Error: dist/template.yaml not found after synth")
        sys.exit(1)

    with open(template_path) as f:
        template = yaml.safe_load(f)

    parameters = template.get("Parameters", {})
    if param_name not in parameters:
        print(f"Error: Parameter {param_name} not found in template")
        print(f"Add this parameter to your CDK stack for version {version}")
        print()
        print("Expected parameter names in template:")
        ami_params = [p for p in parameters.keys() if "Ami" in p]
        for p in ami_params[:5]:
            print(f"  - {p}")
        sys.exit(1)

    print(f"  ✓ Parameter {param_name} found in template")
    return True


def publish_template(version: str) -> str:
    """Publish template to S3 and return the URL."""
    print("Publishing template to S3...")

    result = subprocess.run(
        ["bash", "/scripts/publish-template.sh", version],
        capture_output=True,
        text=True
    )

    if result.returncode != 0:
        print(f"Error: Failed to publish template")
        print(result.stderr)
        sys.exit(1)

    # Extract URL from output
    for line in result.stdout.split("\n"):
        if "https://" in line and ".s3.amazonaws.com" in line:
            url = line.strip()
            if url.startswith("Copied to "):
                url = url[len("Copied to "):]
            print(f"  ✓ Published to {url}")
            return url

    # Construct URL if not found in output
    config = load_config()
    bucket = config.get("template_bucket")
    pattern = config.get("template_pattern")
    url = f"https://{bucket}.s3.amazonaws.com/{pattern}/{version}/template.yaml"
    print(f"  ✓ Template URL: {url}")
    return url


def cmd_submit(args):
    """Submit a new AMI version to AWS Marketplace."""
    config = load_config()

    # Validate required config
    product_id = config.get("product_id", "").strip()
    if not product_id:
        print("Error: product_id not set in marketplace_config.yaml")
        sys.exit(1)

    ami_access_role_arn = config.get("ami_access_role_arn", "").strip()
    if not ami_access_role_arn:
        print("Error: ami_access_role_arn not set in marketplace_config.yaml")
        sys.exit(1)

    print("Validating configuration...")
    print(f"  ✓ Product ID: {product_id}")
    print(f"  ✓ AMI access role ARN configured")
    print()

    # Validate template parameter exists
    print("Validating CloudFormation template...")
    validate_template_parameter(config, args.version)
    print()

    # Publish template
    template_url = publish_template(args.version)
    print()

    # Parse release notes
    print("Parsing release notes from CHANGELOG.md...")
    release_notes = parse_changelog(args.version)
    print(f"  ✓ Found release notes for version {args.version}")
    print()

    # Build the AddDeliveryOptions request
    ami_param_name = get_ami_parameter_name(config, args.version)

    delivery_options = [
        {
            "Details": {
                "AmiDeliveryOptionDetails": {
                    "AmiSource": {
                        "AmiId": args.ami_id,
                        "AccessRoleArn": ami_access_role_arn,
                        "UserName": config.get("username", "ubuntu"),
                        "OperatingSystemName": config.get("operating_system", "UBUNTU"),
                        "OperatingSystemVersion": config.get("operating_system_version", "24.04"),
                    },
                    "UsageInstructions": "See the GitHub repository for documentation: https://github.com/ordinaryexperts/aws-marketplace-oe-patterns-open-webui",
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
        }
    ]

    # Add CloudFormation delivery option
    cfn_details = {
        "CloudFormationDeliveryOptionDetails": {
            "DeliveryOptionTitle": f"CloudFormation Template v{args.version}",
            "TemplateUrl": template_url,
        }
    }

    # Add optional fields
    arch_diagram_url = config.get("architecture_diagram_url", "").strip()
    if arch_diagram_url:
        cfn_details["CloudFormationDeliveryOptionDetails"]["ArchitectureDiagramUrl"] = arch_diagram_url

    calc_url = config.get("aws_calculator_url", "").strip()
    if calc_url:
        cfn_details["CloudFormationDeliveryOptionDetails"]["AWSCalculatorUrl"] = calc_url

    delivery_options.append({"Details": cfn_details})

    details_document = {
        "Version": {
            "VersionTitle": args.version,
            "ReleaseNotes": release_notes
        },
        "DeliveryOptions": delivery_options
    }

    change_set = [
        {
            "ChangeType": "AddDeliveryOptions",
            "Entity": {
                "Type": "AmiProduct@1.0",
                "Identifier": product_id
            },
            "DetailsDocument": details_document
        }
    ]

    print("Submitting version to AWS Marketplace...")

    client = get_catalog_client()

    try:
        response = client.start_change_set(
            Catalog="AWSMarketplace",
            ChangeSet=change_set
        )
    except Exception as e:
        print(f"Error submitting change set: {e}")
        sys.exit(1)

    changeset_id = response.get("ChangeSetId")
    changeset_arn = response.get("ChangeSetArn")

    print(f"  ✓ Change set created: {changeset_id}")
    print()

    # Save changeset ID for status command
    with open(CHANGESET_FILE, "w") as f:
        json.dump({
            "changeset_id": changeset_id,
            "changeset_arn": changeset_arn,
            "version": args.version,
            "ami_id": args.ami_id
        }, f, indent=2)

    print(f"Change set ID saved to {CHANGESET_FILE}")
    print("Check status with: make marketplace-status")
    print()
    print("Note: Version submission can take a few hours to complete.")

    return 0


# -----------------------------------------------------------------------------
# Status command
# -----------------------------------------------------------------------------

def cmd_status(args):
    """Check submission status."""
    changeset_id = args.changeset_id

    # Try to load from file if not provided
    if not changeset_id:
        changeset_path = Path(CHANGESET_FILE)
        if not changeset_path.exists():
            print(f"Error: No changeset ID provided and {CHANGESET_FILE} not found")
            print("Run 'make marketplace-submit' first, or provide CHANGESET_ID=xxx")
            sys.exit(1)

        with open(changeset_path) as f:
            data = json.load(f)
            changeset_id = data.get("changeset_id")

    print(f"Change set: {changeset_id}")

    client = get_catalog_client()

    try:
        response = client.describe_change_set(
            Catalog="AWSMarketplace",
            ChangeSetId=changeset_id
        )
    except Exception as e:
        print(f"Error describing change set: {e}")
        sys.exit(1)

    status = response.get("Status")
    start_time = response.get("StartTime")
    end_time = response.get("EndTime")

    print(f"Status: {status}")
    if start_time:
        print(f"Started: {start_time}")
    if end_time:
        print(f"Ended: {end_time}")

    print()

    if status == "SUCCEEDED":
        print("Version submission succeeded!")
        return 0
    elif status == "FAILED":
        print("Version submission failed.")
        print()
        # Show error details
        change_set = response.get("ChangeSet", [])
        for change in change_set:
            error_details = change.get("ErrorDetailList", [])
            for error in error_details:
                print(f"Error: {error.get('ErrorCode')}")
                print(f"Message: {error.get('ErrorMessage')}")
        return 1
    elif status == "CANCELLED":
        print("Version submission was cancelled.")
        return 1
    else:
        print("Version submission is in progress. This can take a few hours.")
        return 0


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="AWS Marketplace Catalog API automation"
    )
    subparsers = parser.add_subparsers(dest="command", help="Commands")

    # validate command
    validate_parser = subparsers.add_parser(
        "validate",
        help="Check product exists and has required metadata"
    )
    validate_parser.set_defaults(func=cmd_validate)

    # submit command
    submit_parser = subparsers.add_parser(
        "submit",
        help="Submit a new AMI version"
    )
    submit_parser.add_argument(
        "--ami-id",
        required=True,
        help="AMI ID to submit"
    )
    submit_parser.add_argument(
        "--version",
        required=True,
        help="Version string (e.g., 1.0.0)"
    )
    submit_parser.set_defaults(func=cmd_submit)

    # status command
    status_parser = subparsers.add_parser(
        "status",
        help="Check submission status"
    )
    status_parser.add_argument(
        "--changeset-id",
        help="Change set ID (reads from .marketplace_changeset if not provided)"
    )
    status_parser.set_defaults(func=cmd_status)

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
