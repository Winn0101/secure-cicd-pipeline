package terraform

# Terraform Security Policy

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow if all checks pass
allow if {
    not deny_missing_encryption
    not deny_public_access
    not deny_missing_tags
    not deny_insecure_security_group
    not deny_unencrypted_ebs
    not deny_s3_public_access
}

# Deny resources without encryption
deny_missing_encryption if {
    some resource in input.resources
    resource.type in data.encryption_required
    not resource_has_encryption(resource)
}

resource_has_encryption(resource) if {
    resource.values.encryption == true
}

resource_has_encryption(resource) if {
    resource.values.encrypted == true
}

resource_has_encryption(resource) if {
    resource.values.server_side_encryption_configuration
}

resource_has_encryption(resource) if {
    resource.values.kms_key_id
}

# Deny public access to sensitive resources
deny_public_access if {
    some resource in input.resources
    resource.type in data.public_access_prohibited
    resource_is_public(resource)
}

resource_is_public(resource) if {
    resource.values.publicly_accessible == true
}

resource_is_public(resource) if {
    resource.type == "aws_s3_bucket"
    some acl in resource.values.acl
    acl in ["public-read", "public-read-write"]
}

# Deny resources missing required tags
deny_missing_tags if {
    some resource in input.resources
    not has_required_tags(resource)
}

has_required_tags(resource) if {
    every tag in data.required_tags {
        resource.values.tags[tag]
    }
}

# Deny insecure security groups
deny_insecure_security_group if {
    some resource in input.resources
    resource.type == "aws_security_group"
    has_dangerous_ingress(resource)
}

has_dangerous_ingress(sg) if {
    some rule in sg.values.ingress
    rule.cidr_blocks[_] == "0.0.0.0/0"
    rule.from_port <= 22
    rule.to_port >= 22
}

has_dangerous_ingress(sg) if {
    some rule in sg.values.ingress
    rule.cidr_blocks[_] == "0.0.0.0/0"
    rule.from_port <= 3389
    rule.to_port >= 3389
}

# Deny unencrypted EBS volumes
deny_unencrypted_ebs if {
    some resource in input.resources
    resource.type == "aws_ebs_volume"
    not resource.values.encrypted
}

# Deny S3 buckets with public access
deny_s3_public_access if {
    some resource in input.resources
    resource.type == "aws_s3_bucket_public_access_block"
    not all_public_access_blocked(resource)
}

all_public_access_blocked(resource) if {
    resource.values.block_public_acls == true
    resource.values.block_public_policy == true
    resource.values.ignore_public_acls == true
    resource.values.restrict_public_buckets == true
}

# Violations
violations[msg] {
    deny_missing_encryption
    resources := [r | 
        some r in input.resources
        r.type in data.encryption_required
        not resource_has_encryption(r)
    ]
    msg := sprintf("Resources missing encryption: %v", [resources])
}

violations[msg] {
    deny_public_access
    resources := [r | 
        some r in input.resources
        resource_is_public(r)
    ]
    msg := sprintf("Resources with public access: %v", [resources])
}

violations[msg] {
    deny_missing_tags
    resources := [r | 
        some r in input.resources
        not has_required_tags(r)
    ]
    msg := sprintf("Resources missing required tags: %v", [resources])
}

violations[msg] {
    deny_insecure_security_group
    msg := "Security group allows unrestricted access to SSH/RDP"
}

violations[msg] {
    deny_unencrypted_ebs
    msg := "EBS volumes must be encrypted"
}

violations[msg] {
    deny_s3_public_access
    msg := "S3 buckets must block all public access"
}

get_violations := violations
