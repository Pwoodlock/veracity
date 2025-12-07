# Security Test Suite

This directory contains comprehensive security tests for the Veracity application, focusing on protecting against common web application vulnerabilities.

## Test Files

### 1. CSRF Protection Tests (`csrf_protection_test.rb`)

**Purpose:** Verify Cross-Site Request Forgery (CSRF) protection is enforced for all state-changing operations.

**Tests (7 total):**
1. POST to servers without CSRF token returns 422
2. PATCH to server without CSRF token returns 422
3. DELETE to server without CSRF token returns 422
4. POST to execute task without CSRF token returns 422
5. Document CSRF-exempt endpoints (currently none)
6. Verify CSRF protection enabled in test environment
7. Verify valid CSRF tokens allow operations

**Key Security Controls:**
- Rails' built-in CSRF protection enabled
- All POST/PATCH/PUT/DELETE requests require valid CSRF tokens
- Session-based authentication (Devise) requires CSRF
- No CSRF exemptions currently (all endpoints protected)

**Reference:** [OWASP CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)

---

### 2. SQL Injection Tests (`sql_injection_test.rb`)

**Purpose:** Verify user input is properly sanitized to prevent SQL injection attacks.

**Tests (7 total):**
1. Server search filters SQL injection payloads safely
2. CVE watchlist vendor/product search prevents SQL injection
3. Group filtering with malicious input
4. Order/sort parameter injection protection
5. Verify parameterized queries are used
6. Verify ActiveRecord sanitization prevents injection
7. Test vulnerable patterns don't exist in codebase

**SQL Injection Payloads Tested:**
- `'; DROP TABLE servers; --` (Classic injection)
- `' OR '1'='1` (Authentication bypass)
- `' UNION SELECT * FROM users --` (Data extraction)
- `admin'--` (Comment injection)
- `1' AND '1'='1` (Logical AND injection)

**Key Security Controls:**
- All queries use ActiveRecord's parameterized queries
- No string interpolation in WHERE clauses
- User input treated as literal text, not SQL code
- Search functionality uses `?` placeholders

**Reference:** [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)

---

### 3. Command Injection Tests (`command_injection_test.rb`)

**Purpose:** Verify user input passed to system commands is properly sanitized.

**Tests (7 total):**
1. Salt CLI rejects commands with dangerous shell metacharacters
2. execute_shell properly escapes malicious arguments
3. Snapshot name validation rejects shell metacharacters
4. Python script execution escapes shell metacharacters
5. Verify command boundaries cannot be escaped
6. File path traversal in Salt state names
7. Verify SaltService uses JSON-RPC, not shell

**Command Injection Payloads Tested:**
- `; rm -rf /` (Command chaining with semicolon)
- `&& rm -rf /` (Command chaining with AND)
- `|| rm -rf /` (Command chaining with OR)
- `| cat /etc/passwd` (Pipe to another command)
- `$(whoami)` (Command substitution)
- `` `whoami` `` (Backtick command substitution)

**Key Security Controls:**
- Salt API uses JSON-RPC over HTTP (not shell execution)
- Commands sent as structured data, not concatenated strings
- Snapshot names validated with regex: `/\A[a-zA-Z0-9_-]+\z/`
- Shell metacharacters rejected before reaching system calls
- SaltService never uses `system()`, `exec()`, or backticks

**Reference:** [OWASP Command Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html)

---

## Running Security Tests

### Run all security tests:
```bash
bundle exec rails test test/security/
```

### Run individual test files:
```bash
bundle exec rails test test/security/csrf_protection_test.rb
bundle exec rails test test/security/sql_injection_test.rb
bundle exec rails test test/security/command_injection_test.rb
```

### Run with verbose output:
```bash
bundle exec rails test test/security/ -v
```

---

## Test Coverage Summary

| Category | Tests | Key Vulnerabilities Protected |
|----------|-------|------------------------------|
| CSRF Protection | 7 | Cross-Site Request Forgery |
| SQL Injection | 7 | Database manipulation, data theft |
| Command Injection | 7 | System compromise, arbitrary command execution |
| **Total** | **21** | **3 critical vulnerability classes** |

---

## Security Testing Principles

### 1. Defense in Depth
- Multiple layers of protection (input validation, parameterization, escaping)
- Each layer tested independently

### 2. Fail Securely
- Invalid input is rejected, not processed
- Errors don't expose sensitive information
- System remains secure even if one layer fails

### 3. Never Trust User Input
- All user input is considered malicious
- Input validation happens before processing
- Whitelist approach preferred over blacklist

### 4. Separation of Code and Data
- SQL: Use parameterized queries (ActiveRecord)
- Shell: Use JSON-RPC API, not shell execution
- Never concatenate user input into commands

---

## Integration with Salt Stack

### Salt API Security Architecture

Salt API provides built-in protection against command injection:

1. **JSON-RPC Communication:** All commands sent as structured JSON data
2. **No Shell Execution:** Salt API doesn't execute commands via shell
3. **Minion Context:** Commands executed in controlled subprocess on minion
4. **Function-based Execution:** Uses Salt functions (`cmd.run`, `state.apply`), not arbitrary shell

### Command Flow:
```
User Input → Rails Controller → SaltService
           → JSON-RPC → Salt API → Salt Master
           → Salt Minion → Controlled Subprocess
```

At no point does user input get concatenated into a shell command.

---

## Best Practices Enforced

### CSRF Protection
✅ All state-changing endpoints require CSRF tokens
✅ Session-based authentication (Devise) properly configured
✅ No CSRF exemptions (all endpoints protected)

### SQL Injection Prevention
✅ ActiveRecord parameterized queries only
✅ No string interpolation in WHERE clauses
✅ User input sanitized before database queries

### Command Injection Prevention
✅ Salt API JSON-RPC (no shell execution)
✅ Input validation (whitelists for names/identifiers)
✅ No use of `system()`, `exec()`, or backticks
✅ Commands sent as structured data arrays

---

## Future Enhancements

If additional security features are added, update these tests:

1. **Token-based API endpoints:** Add CSRF exemption documentation
2. **Webhook endpoints:** Verify signature-based authentication
3. **File uploads:** Add tests for file type validation and sanitization
4. **GraphQL API:** Add tests for query depth limiting and injection
5. **WebSocket endpoints:** Add tests for authentication and authorization

---

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)
- [OWASP Command Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/OS_Command_Injection_Defense_Cheat_Sheet.html)
- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
- [Salt Security Best Practices](https://docs.saltproject.io/en/latest/topics/hardening.html)

---

## Verification Checklist

Before deploying to production, verify:

- [ ] All 21 security tests pass
- [ ] No CSRF violations in application logs
- [ ] No SQL errors in application logs (indicates potential injection attempts)
- [ ] Salt API authentication working correctly
- [ ] Encrypted credentials (Hetzner, Proxmox, NetBird) never appear in logs
- [ ] Rate limiting configured (Rack::Attack)
- [ ] Session security configured (secure, httponly cookies)
- [ ] HTTPS enforced in production
- [ ] Security headers configured (CSP, X-Frame-Options, etc.)

---

Last Updated: 2025-12-07
Test Count: 21 tests (7 CSRF + 7 SQL injection + 7 command injection)
