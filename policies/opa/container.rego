package container

# Container Security Policy

# METADATA
# title: Container Security Policy
# description: Enforces container security best practices
# custom:
#   severity: HIGH

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow if all checks pass
allow if {
    not deny_latest_tag
    not deny_root_user
    not deny_exposed_secrets
    not deny_unapproved_base_image
    not deny_missing_labels
    not deny_vulnerable_packages
}

# Deny latest tag
deny_latest_tag if {
    input.image_tag == "latest"
}

# Deny running as root
deny_root_user if {
    input.user == "root"
}

deny_root_user if {
    input.user == "0"
}

deny_root_user if {
    not input.user
}

# Deny exposed secrets
deny_exposed_secrets if {
    some secret in input.secrets_found
    secret.severity == "HIGH"
}

# Deny unapproved base images
deny_unapproved_base_image if {
    not approved_base_image
}

approved_base_image if {
    some allowed in data.allowed_base_images
    startswith(input.base_image, allowed)
}

# Deny missing required labels
deny_missing_labels if {
    some required in data.required_labels
    not input.labels[required]
}

# Deny vulnerable packages
deny_vulnerable_packages if {
    some vuln in input.vulnerabilities
    vuln.severity in ["CRITICAL", "HIGH"]
    not vuln.fixed_version
}

# Violation details
violations[msg] {
    deny_latest_tag
    msg := "Image uses 'latest' tag which is prohibited"
}

violations[msg] {
    deny_root_user
    msg := "Container runs as root user which is prohibited"
}

violations[msg] {
    deny_exposed_secrets
    msg := sprintf("Secrets detected in image: %v", [input.secrets_found])
}

violations[msg] {
    deny_unapproved_base_image
    msg := sprintf("Base image '%s' is not in approved list", [input.base_image])
}

violations[msg] {
    deny_missing_labels
    missing := {label | 
        some label in data.required_labels
        not input.labels[label]
    }
    count(missing) > 0
    msg := sprintf("Missing required labels: %v", [missing])
}

violations[msg] {
    deny_vulnerable_packages
    critical_vulns := [vuln | 
        some vuln in input.vulnerabilities
        vuln.severity in ["CRITICAL", "HIGH"]
    ]
    count(critical_vulns) > 0
    msg := sprintf("Found %d critical/high vulnerabilities", [count(critical_vulns)])
}

# Helper: Get all violations
get_violations := violations
