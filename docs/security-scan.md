Container Security Scan
Scope
Trivy was used to scan the local Docker image cloudrun-svc:local. The full scan and fixable-only scan outputs are retained in docs/evidence/.
Results
HIGH findings: 44
CRITICAL findings: 0
The findings include Debian 13.7 operating-system packages such as bsdutils, libncursesw6, and libtinfo6.
The fixable-only report lists the scanned Debian and Python package targets with zero detected vulnerabilities. This result depends on the Trivy filters and configuration used to produce that report. It does not establish that the image is vulnerability-free.
Evidence files
evidence/trivy-full.txt — full Trivy scan output.
evidence/trivy-fixable.txt — fixable-only scan output.
evidence/docker-health.txt — local container health-check evidence.
evidence/pr-checks-green.png — pull-request workflow screenshot.
CI policy
The pull-request workflow runs Trivy against the built image. Its configured policy fails on HIGH and CRITICAL findings that remain in scope after configured filters, including --ignore-unfixed.
This is intended to block actionable high-severity findings. It does not guarantee that every dependency is free of vulnerabilities.
Limitations and remediation
Scan results reflect the image and vulnerability database at the time of scanning. Vulnerability details and fix availability can change.
Before production deployment:
Review each finding and confirm whether a vendor fix is available.
Update the base image and affected packages where safe and supported.
Rebuild the image and rerun both scans.
Retain the updated reports and review the CI policy.
Do not interpret zero CRITICAL findings as proof of zero security risk.
 