# Auto-Assignment System Documentation

## Overview

The Auto-Assignment System intelligently routes task groups to specialized agents based on keyword analysis and machine learning. It learns from your corrections over time to continuously improve assignment accuracy.

## Table of Contents

1. [How It Works](#how-it-works)
2. [Getting Started](#getting-started)
3. [Understanding Confidence Scores](#understanding-confidence-scores)
4. [Learning System](#learning-system)
5. [Configuration](#configuration)
6. [Examples](#examples)
7. [Troubleshooting](#troubleshooting)
8. [FAQ](#faq)

## How It Works

### The Process

When you run `/implement-tasks`, the system:

1. **Analyzes** each task group's name and description
2. **Extracts keywords** to identify task type (frontend, backend, database, etc.)
3. **Checks learning history** for similar patterns you've corrected before
4. **Calculates scores** for each specialized agent
5. **Recommends** the best-matching agent with confidence score
6. **Presents plan** for your review and approval
7. **Learns** from your corrections to improve future assignments

### Keyword-Based Classification

The system looks for specific keywords in your task names/descriptions:

| Category | Example Keywords | Assigned Agent |
|----------|-----------------|----------------|
| **Frontend** | component, button, form, modal, react, tailwind, ui | frontend-developer, Daisy-UI-Agent |
| **Backend** | endpoint, controller, api, service, model, rails | implementer, python-pro |
| **Database** | migration, schema, table, index, query, sql | database-architect |
| **Testing** | test, spec, unit, integration, rspec | implementer, code-reviewer |
| **Security** | auth, csrf, injection, validation, encryption | code-reviewer |
| **Deployment** | ci/cd, docker, kubernetes, pipeline, deploy | deployment-engineer |
| **AI/ML** | llm, rag, embedding, prompt, vector | ai-engineer |

**Tip:** Use descriptive task group names! "Frontend Dashboard Component" will get better assignments than "Update UI".

## Getting Started

### Your First Auto-Assignment

1. **Create a spec** with task groups using `/shape-spec` and `/create-tasks`

2. **Run `/implement-tasks`**
   ```
   You: /implement-tasks
   ```

3. **Review the auto-assignment plan**
   ```
   Auto-Assignment Plan:

   1. User Authentication System
      → Agent: code-reviewer
      → Confidence: 92%
      → Standards: all

   2. Dashboard UI Components
      → Agent: frontend-developer
      → Confidence: 88%
      → Standards: global/*, frontend/*
   ```

4. **Respond with your choice**
   - `yes` - Accept all assignments
   - `no` - Use generic implementer instead
   - `manual` - Switch to `/orchestrate-tasks`
   - `change 2` - Manually specify agent for task #2

### Approving Assignments

**If confidence is high (≥90%):**
```
1. Database Schema Migration
   → Agent: database-architect ✅
   → Confidence: 95%
```
Just say `yes` - the system is very confident!

**If confidence is medium (70-89%):**
```
2. API Endpoint Implementation
   → Agent: implementer
   → Confidence: 82%
```
Review and confirm - usually correct but verify it makes sense.

**If confidence is low (<70%):**
```
3. Generic Refactoring Task
   → Agent: implementer ⚠️ Low confidence - please confirm
   → Confidence: 62%
```
**Please review carefully!** Consider changing the agent or using `/orchestrate-tasks` for manual control.

## Understanding Confidence Scores

### What Confidence Means

- **≥90% (High)**: Strong keyword match, clear task type
- **70-89% (Medium)**: Good match, but some ambiguity
- **<70% (Low)**: Weak match, manual review recommended

### What Affects Confidence

**Increases confidence:**
- Clear, descriptive task names
- Keywords matching agent's primary capabilities
- Learning bonuses from past corrections
- Single-domain tasks (e.g., pure frontend)

**Decreases confidence:**
- Vague task names ("Miscellaneous updates")
- Multi-domain tasks (frontend + backend + database)
- Keywords not in system's vocabulary
- Conflicting keywords

### Improving Confidence

**Before:**
```
Task: "Fix stuff"
→ Agent: implementer ⚠️
→ Confidence: 45%
```

**After:**
```
Task: "Fix CSRF validation in authentication controller"
→ Agent: code-reviewer ✅
→ Confidence: 95%
```

**Best Practices:**
1. Use specific, descriptive task names
2. Include technology keywords (React, Rails, PostgreSQL, etc.)
3. Mention the layer (UI, API, database, etc.)
4. Indicate complexity if relevant

## Learning System

### How Learning Works

The system tracks every assignment you make:

**When you confirm an assignment:**
```
✅ Saved: "Frontend dashboard component" → frontend-developer
```

**When you correct an assignment:**
```
✨ Learned: "CI workflow fixes" → deployment-engineer (was: implementer)
```

**Next time similar task appears:**
```
Auto-Assignment Plan:

1. CI Pipeline Enhancement
   → Agent: deployment-engineer ✨ Learned from previous correction
   → Confidence: 95% (was 65%)
```

### Learning Indicators

| Indicator | Meaning |
|-----------|---------|
| ✨ Learned from previous correction | System applied +15 point bonus from your past correction |
| ✅ | High confidence (≥90%) |
| ⚠️ | Low confidence (<70%) - please review |

### Viewing Learning Statistics

Check your assignment history:
```bash
cat agent-os/data/assignment-history.yml
```

Example output:
```yaml
stats:
  total_assignments: 25
  auto_confirmed: 21
  user_corrected: 4
  accuracy: 84.0%
  last_updated: 2025-12-08T15:30:00Z
```

**Accuracy improves over time:**
- First 5 assignments: ~75% accuracy
- After 20 assignments: ~85% accuracy
- After 50 assignments: ~90%+ accuracy

### Editing Learning History

**View history:**
```bash
cat agent-os/data/assignment-history.yml
```

**Manually edit** if needed (advanced users):
```bash
nano agent-os/data/assignment-history.yml
```

**Reset learning** (start fresh):
```bash
rm agent-os/data/assignment-history.yml
```

The system will recreate the file on next use.

## Configuration

### Main Configuration File

Location: `agent-os/config/auto-assignment-config.yml`

### Common Settings

**Enable/Disable Auto-Assignment:**
```yaml
enabled: true  # Set to false to use generic implementer only
```

**Adjust Confidence Threshold:**
```yaml
confidence_threshold: 0.7  # Require 70% confidence minimum
                          # Lower = fewer prompts, but more risk
                          # Higher = more prompts, but safer
```

**Enable/Disable Learning:**
```yaml
learning:
  enabled: true  # Set to false for static keyword matching only
```

**Adjust Learning Sensitivity:**
```yaml
learning:
  similarity_threshold: 0.8  # How similar patterns must be (0-1)
                             # 0.8 = 80% keyword overlap required
```

### Adding Custom Keywords

Edit `task_keywords` section:

```yaml
task_keywords:
  frontend:
    - component
    - your-custom-keyword  # Add here
```

### Modifying Agent Capabilities

Edit `agent_capabilities` section:

```yaml
agent_capabilities:
  your-custom-agent:
    primary: [frontend, testing]
    secondary: [backend]
    model: sonnet
```

## Examples

### Example 1: High-Confidence Frontend Task

**Task:**
```
### User Dashboard Component
Create a responsive dashboard component using Tailwind CSS and DaisyUI with:
- User profile card
- Activity feed
- Settings modal
```

**Auto-Assignment:**
```
1. User Dashboard Component
   → Agent: Daisy-UI-Agent ✅
   → Confidence: 96%
   → Standards: global/*, frontend/*

   Matched keywords: dashboard, component, tailwind, daisyui, modal
```

**Result:** Say `yes` - clearly a DaisyUI frontend task!

### Example 2: Security Task with Learning

**First time:**
```
1. Add CSRF Protection to API
   → Agent: implementer
   → Confidence: 68% ⚠️
```

**You correct:**
```
You: change 1
System: Which agent should handle task group 1?
You: code-reviewer
✨ Learned: CSRF tasks → code-reviewer
```

**Next time:**
```
1. Implement Rate Limiting for Auth API
   → Agent: code-reviewer ✨ Learned from previous correction
   → Confidence: 92%

   Applied learning bonus: +15 points
```

### Example 3: Multi-Domain Task

**Task:**
```
### Full-Stack User Management
- Backend: User model and API endpoints
- Frontend: User management UI
- Database: Users table migration
```

**Auto-Assignment:**
```
1. Full-Stack User Management
   → Agent: implementer
   → Confidence: 72%

   Note: Multi-domain task detected
   Matched: backend, frontend, database keywords
```

**Options:**
- Accept implementer (full-stack capable)
- Split into 3 separate task groups
- Use `/orchestrate-tasks` to assign different agents per layer

### Example 4: Low-Confidence Task

**Task:**
```
### Miscellaneous Improvements
Various updates and fixes
```

**Auto-Assignment:**
```
1. Miscellaneous Improvements
   → Agent: implementer ⚠️ Low confidence - please confirm
   → Confidence: 45%
```

**What to do:**
- **Option A:** Say `yes` if implementer is appropriate
- **Option B:** `change 1` to specify correct agent
- **Option C:** Improve task description and re-run `/implement-tasks`
- **Option D:** Use `/orchestrate-tasks` for manual control

## Troubleshooting

### "Low confidence on all tasks"

**Problem:** Every task shows <70% confidence

**Solutions:**
1. **Use more descriptive task names** with technology keywords
2. **Check if keywords are in config** (`auto-assignment-config.yml`)
3. **Add project-specific keywords** to config
4. **Split vague tasks** into more specific sub-tasks

### "Wrong agent assigned"

**Problem:** Agent doesn't match task type

**Solutions:**
1. **Correct the assignment** - system will learn!
2. **Check task description** - does it contain misleading keywords?
3. **Review keyword config** - add/remove keywords as needed
4. **Use `/orchestrate-tasks`** for complex specs requiring manual control

### "System not learning"

**Problem:** Same mistakes repeated

**Solutions:**
1. **Check learning is enabled:**
   ```yaml
   learning:
     enabled: true
   ```
2. **Verify corrections are saved:**
   ```bash
   cat agent-os/data/assignment-history.yml
   ```
3. **Check similarity threshold** - might be too high:
   ```yaml
   learning:
     similarity_threshold: 0.8  # Try lowering to 0.7
   ```

### "Accuracy decreasing"

**Problem:** Accuracy going down over time

**Possible causes:**
1. **Inconsistent corrections** - assigning different agents for similar tasks
2. **Task variety increased** - new types of tasks not seen before
3. **History file corrupted** - check YAML syntax

**Solutions:**
- Review and clean up history file
- Be consistent with corrections
- Consider resetting history if corrupted

## FAQ

### Q: Can I disable auto-assignment?

**A:** Yes! Set `enabled: false` in `agent-os/config/auto-assignment-config.yml`. The system will fall back to using the generic implementer for all tasks.

### Q: What if I want full manual control?

**A:** Use `/orchestrate-tasks` instead of `/implement-tasks`. It provides complete manual control over agent assignment and standards selection.

### Q: How is this different from `/orchestrate-tasks`?

**A:**

| Feature | /implement-tasks | /orchestrate-tasks |
|---------|-----------------|-------------------|
| Agent Assignment | Automatic with option to override | Fully manual |
| Speed | Fast (one confirmation) | Slower (configure everything) |
| Learning | Yes | No |
| Best For | Simple to medium specs | Complex specs, full control |

### Q: Does learning data sync across machines?

**A:** No, learning history is stored locally in `agent-os/data/assignment-history.yml`. You can manually copy this file to sync learning across machines or commit it to your repository.

### Q: Can I pre-seed learning data?

**A:** Yes! Manually edit `agent-os/data/assignment-history.yml` and add entries. Follow the schema shown in the file comments.

### Q: What happens if an agent doesn't exist?

**A:** The system will detect this and fall back to the generic implementer with a warning. Make sure agent names in config match actual agents in `.claude/agents/`.

### Q: Can I assign multiple agents to one task group?

**A:** No, each task group gets one agent. If you need multiple agents, split the task group into smaller, agent-specific task groups.

### Q: Will this work with custom agents I create?

**A:** Yes! Add your custom agent to `agent_capabilities` in `auto-assignment-config.yml` and define its primary/secondary capabilities.

### Q: How do I see what keywords matched?

**A:** Set `display.show_matched_keywords: true` in config. The system will show which keywords triggered the assignment.

### Q: Can I change confidence threshold per task?

**A:** No, it's global. But you can override any individual assignment with `change [number]`.

### Q: What if I make a mistake correcting?

**A:** Edit `agent-os/data/assignment-history.yml` and remove the incorrect entry, or let the system re-learn from future correct assignments.

## Best Practices

1. **Use descriptive task names** - Include technology, layer, and domain
2. **Review low-confidence assignments** - Don't blindly accept <70%
3. **Correct mistakes** - System learns from your corrections
4. **Check learning stats periodically** - Monitor accuracy trends
5. **Update keywords** - Add project-specific terms to config
6. **Split multi-domain tasks** - Clearer assignments, higher confidence
7. **Consistent corrections** - Assign same agent for similar tasks

## Getting Help

**Issues or questions?**
- Check this documentation first
- Review `agent-os/services/agent_assignment_service.md` for technical details
- Examine `agent-os/config/auto-assignment-config.yml` for current settings
- Inspect `agent-os/data/assignment-history.yml` to see learning data

**Want to contribute?**
- Suggest keyword additions
- Report incorrect assignments
- Share accuracy improvements
- Propose new agent capabilities
