# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in TermQ, please report it responsibly:

1. **Do not** open a public GitHub issue
2. Email the maintainers directly or use GitHub's private vulnerability reporting
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Any suggested fixes (optional)

We will acknowledge receipt within 48 hours and aim to provide a fix within 7 days for critical issues.

## Security Considerations

TermQ runs terminal sessions with your user privileges. Be aware that:

- Terminal sessions have full access to your shell environment
- The CLI tool (`termq open`) can be invoked by any process
- Board data is stored unencrypted in `~/Library/Application Support/TermQ/`
