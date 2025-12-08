# Requirements: System Verification & Validation Suite

## User Answers Summary

### Verification Approach
| Question | Answer |
|----------|--------|
| Testing style | Automated tests (unit, integration, system) |
| Environment | Live staging server (46.224.101.253) - can be reset |
| Test framework | Enhance existing Minitest (not replace) |
| Test location | Run directly on server for speed |

### Priority and Scope
| Question | Answer |
|----------|--------|
| Priority features | ALL - Salt operations, security features, AND cloud integrations |
| Scope | Everything - Rails app, install scripts, systemd services |
| Intelligence | Test changes don't break existing functionality (regression) |
| Frontend | Use DaisyUI agent for visual/frontend work |

### Success Criteria
| Question | Answer |
|----------|--------|
| Definition of "working" | Functional correctness + error handling |
| Performance benchmarks | Not required |
| Security testing | YES - all 7 recommended tests |

### CI/CD and Monitoring
| Question | Answer |
|----------|--------|
| Runtime health checks | YES - for production |
| GitHub workflows | Need fixing - Claude integration |
| Docusaurus | Set up in WSL |

## Test Infrastructure

### Staging Environment
- **Server**: 46.224.101.253
- **Access**: SSH with firewall (IP-restricted)
- **Reset**: Can be reset via installer at any time
- **Test Minion**: `n8n` (safe for destructive tests)

### Test Data Strategy
1. **Factory-based** - Use FactoryBot for isolated test data
2. **Database transactions** - Rollback after each test
3. **Preserve staging** - Don't touch existing servers/watchlists
4. **Integration tests** - Use `n8n` minion or read-only operations

## Security Tests Required

| # | Test | Reason |
|---|------|--------|
| 1 | CSRF Protection | Ensure state-changing endpoints reject invalid tokens |
| 2 | SQL Injection | Verify parameterized queries in dynamic commands |
| 3 | Command Injection | Test Salt CLI and Python script input sanitization |
| 4 | Session Security | Verify timeout, secure cookies, session invalidation |
| 5 | Authorization (Pundit) | Users only access authorized resources |
| 6 | Encrypted Credentials | API keys encrypted at rest, never logged plaintext |
| 7 | Rate Limiting | Rack::Attack blocks brute force attempts |

## GitHub Workflow Fixes Required

### ci.yml
- **Issue**: `docs` job condition uses `github.event.pull_request.changed_files` incorrectly
- **Fix**: Use `paths` filter or `dorny/paths-filter` action

### claude.yml
- **Issue**: Missing write permissions
- **Fix**: Add `contents: write`, `pull-requests: write`, `issues: write`

### claude-code-review.yml
- **Issue**: Missing `pull-requests: write` permission
- **Fix**: Add permission for Claude to post review comments

### deploy-docs.yml
- **Status**: Node 24 is correct (Active LTS as of late 2025)
- **Verify**: Ensure workflow runs successfully with Node 24

## Additional Setup Tasks

### Docusaurus Local Development
1. Install Node.js 20 in WSL
2. Run `npm install` in `/docs` folder
3. Verify `npm run build` works
4. Test `npm run start` for local dev server

## Visual Assets
- **Location**: `agent-os/specs/2025-12-07-system-verification/planning/visuals/`
- **Source**: Existing frontend code (no mockups needed - UI is complete)
