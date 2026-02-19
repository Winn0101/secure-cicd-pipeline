package deployment

# Deployment Policy

import future.keywords.if
import future.keywords.in

# Default deny
default allow := false

# Allow deployment based on environment
allow if {
    input.environment == "development"
    development_checks_pass
}

allow if {
    input.environment == "staging"
    staging_checks_pass
}

allow if {
    input.environment == "production"
    production_checks_pass
}

# Development environment checks
development_checks_pass if {
    not deny_failed_tests
    not deny_security_violations
}

# Staging environment checks
staging_checks_pass if {
    not deny_failed_tests
    not deny_security_violations
    not deny_policy_violations
}

# Production environment checks
production_checks_pass if {
    not deny_failed_tests
    not deny_security_violations
    not deny_policy_violations
    not deny_missing_approval
    not deny_outside_deployment_window
    has_green_build
}

# Deny if tests failed
deny_failed_tests if {
    input.test_results.failed > 0
}

# Deny if security scan found critical issues
deny_security_violations if {
    input.security_scan.critical_count > 0
}

deny_security_violations if {
    input.security_scan.high_count > data.max_high_vulnerabilities
}

# Deny if policy violations found
deny_policy_violations if {
    count(input.policy_violations) > 0
}

# Deny if missing approval for production
deny_missing_approval if {
    input.environment == "production"
    not input.approval.approved
}

# Deny if outside deployment window
deny_outside_deployment_window if {
    input.environment == "production"
    not in_deployment_window
}

in_deployment_window if {
    current_day := input.deployment_time.day
    current_day in data.deployment_window.days
    current_hour := input.deployment_time.hour
    current_hour >= data.deployment_window.hours[0]
    current_hour <= data.deployment_window.hours[1]
}

# Require green build status
has_green_build if {
    input.build_status == "success"
}

# Break-glass emergency deployment
allow if {
    input.break_glass.enabled == true
    input.break_glass.approved == true
    input.break_glass.justification != ""
}

# Violations
violations[msg] {
    deny_failed_tests
    msg := sprintf("Tests failed: %d failures", [input.test_results.failed])
}

violations[msg] {
    deny_security_violations
    msg := sprintf("Security scan found %d critical and %d high vulnerabilities", 
        [input.security_scan.critical_count, input.security_scan.high_count])
}

violations[msg] {
    deny_policy_violations
    msg := sprintf("Policy violations: %v", [input.policy_violations])
}

violations[msg] {
    deny_missing_approval
    msg := "Production deployment requires approval"
}

violations[msg] {
    deny_outside_deployment_window
    msg := "Deployment outside allowed time window"
}

get_violations := violations

# Recommendations
recommendations[msg] {
    input.security_scan.medium_count > 5
    msg := "Consider fixing medium severity vulnerabilities before deploying"
}

recommendations[msg] {
    not input.deployment_metadata.rollback_plan
    msg := "Deployment missing rollback plan"
}

recommendations[msg] {
    input.environment == "production"
    not input.deployment_metadata.monitoring_enabled
    msg := "Enable enhanced monitoring for production deployment"
}
