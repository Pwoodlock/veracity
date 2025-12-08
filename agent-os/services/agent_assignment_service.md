# Agent Assignment Service

This service provides intelligent auto-assignment of specialized agents to task groups based on keyword analysis and machine learning from past corrections.

## Overview

The Agent Assignment Service analyzes task group names and descriptions to automatically recommend the most appropriate specialized agent. It learns from your manual corrections over time to improve assignment accuracy.

## How It Works

### 1. Keyword Extraction

Extract keywords from task group name and description to classify the task type.

**Keyword Categories:**

- **Frontend**: component, button, form, modal, layout, responsive, react, tailwind, css, ui, view, jsx, tsx, styling, theme
- **Backend**: endpoint, controller, route, api, service, model, serializer, json, rest, rails, ruby, server
- **Database**: migration, schema, table, index, query, relationship, association, sql, activerecord, postgres, mysql
- **Testing**: test, spec, unit, integration, system, coverage, assertion, rspec, jest, fixture, factory
- **Security**: auth, csrf, injection, encryption, validation, sanitize, rate-limit, xss, sql injection, authentication, authorization
- **Deployment**: ci/cd, docker, kubernetes, pipeline, github actions, deploy, release, staging, production, infrastructure
- **AI/ML**: llm, rag, embedding, prompt, agent, vector, openai, anthropic, gpt, claude, ai

### 2. Agent Capability Mapping

Each specialized agent has primary and secondary capabilities:

```yaml
agent_capabilities:
  frontend-developer:
    primary: [frontend]
    secondary: [testing]
    model: sonnet
    description: React/UI development specialist

  database-architect:
    primary: [database]
    secondary: [backend, performance]
    model: opus
    description: Database design and optimization specialist

  ai-engineer:
    primary: [ai-ml]
    secondary: [backend]
    model: opus
    description: LLM integration and RAG system specialist

  code-reviewer:
    primary: [security, code-quality]
    secondary: [testing]
    model: sonnet
    description: Security auditing and code quality specialist

  deployment-engineer:
    primary: [deployment, infrastructure]
    secondary: []
    model: sonnet
    description: CI/CD and infrastructure automation specialist

  javascript-pro:
    primary: [frontend]
    secondary: [backend, testing]
    model: sonnet
    description: Advanced JavaScript and Node.js specialist

  python-pro:
    primary: [backend]
    secondary: [ai-ml, testing]
    model: sonnet
    description: Python development and optimization specialist

  Daisy-UI-Agent:
    primary: [frontend]
    secondary: []
    model: opus
    description: Tailwind CSS and DaisyUI specialist

  implementer:
    primary: [backend]
    secondary: [frontend, testing]
    model: inherit
    fallback: true
    description: Full-stack general purpose implementer
```

### 3. Scoring Algorithm

**Step 1: Base Scoring**
For each agent, calculate base match score:
- Primary keyword match: **+10 points** per keyword
- Secondary keyword match: **+5 points** per keyword
- Complexity bonus: **+3 points** for opus-model agents on complex tasks

**Step 2: Learning Adjustments**
Load assignment history and apply learned weights:
- User corrected this pattern before: **+15 points** to preferred agent
- Similar task assigned manually: **+10 points** to that agent
- User confirmed low-confidence assignment: **+8 points**

**Step 3: Calculate Confidence**
Convert score to confidence percentage:
```
confidence = (agent_score / max_possible_score) * 100
```

Confidence thresholds:
- **≥ 90%**: High confidence (✅)
- **70-89%**: Medium confidence
- **< 70%**: Low confidence (⚠️ - prompt user)

**Step 4: Pattern Matching for Learning**
When checking history, match patterns based on:
- Keyword similarity (≥80% overlap)
- Task complexity level match
- Category overlap (frontend, backend, etc.)

### 4. Standards Auto-Selection

Each agent type maps to specific standards that should guide their implementation:

```yaml
standards_mapping:
  frontend-developer:
    - global/*
    - frontend/*

  database-architect:
    - global/*
    - backend/models.md
    - backend/migrations.md
    - backend/queries.md

  ai-engineer:
    - global/*
    - backend/api.md  # For API integrations

  code-reviewer:
    - all  # Reviews all code against all standards

  deployment-engineer:
    - global/*
    - global/conventions.md  # Extra emphasis on conventions for infrastructure

  javascript-pro:
    - global/*
    - frontend/*
    - backend/api.md

  python-pro:
    - global/*
    - backend/*

  Daisy-UI-Agent:
    - global/*
    - frontend/*

  implementer:
    - global/*
    - backend/*
    - frontend/*
    - testing/*
```

### 5. Learning System

The service maintains a learning history that improves over time.

**Learning Data Structure:**
```yaml
history:
  - task_pattern: "CI workflow fixes"
    keywords: [ci, workflow, github, actions, pipeline]
    complexity: medium
    auto_assigned: implementer
    user_corrected: deployment-engineer
    timestamp: 2025-12-08T10:30:00Z

  - task_pattern: "Frontend component with Tailwind"
    keywords: [component, tailwind, responsive, button]
    complexity: simple
    auto_assigned: frontend-developer
    user_confirmed: frontend-developer
    confidence_was: 0.92
    timestamp: 2025-12-08T11:15:00Z
```

**Learning Process:**
1. When user corrects an assignment, save pattern to history
2. When user confirms a low-confidence assignment, save as confirmation
3. On next assignment, check if similar patterns exist in history
4. If pattern similarity ≥ 80%, apply learning bonus to preferred agent
5. Update accuracy statistics after each assignment

**Statistics Tracked:**
- Total assignments made
- Auto-confirmed (user said "yes")
- User corrected (user changed assignment)
- Accuracy percentage (confirmed / total)
- Accuracy trend over time

### 6. Assignment Workflow

**Full workflow when assigning agents:**

```
1. Parse task group name + description
2. Extract keywords from text
3. Load assignment history (if exists)
4. For each available agent:
   a. Calculate base score from keyword matches
   b. Apply learning bonuses from history
   c. Calculate final score and confidence
5. Sort agents by score (highest first)
6. Select top agent
7. Check confidence threshold:
   - If ≥ 70%: Recommend with confidence indicator
   - If < 70%: Recommend but flag for user review
8. Select appropriate standards for agent
9. Return assignment recommendation
```

**Output Format:**
```yaml
task_group: "CI Workflow Fixes"
recommended_agent: deployment-engineer
confidence: 0.95
confidence_level: high
learning_applied: true  # Bonus from previous correction
standards:
  - global/*
  - global/conventions.md
keywords_matched: [ci, workflow, github, actions]
alternative_agents:
  - agent: implementer
    confidence: 0.65
```

### 7. Usage Instructions

**When presenting to user:**
```
Auto-Assignment Plan:

1. CI Workflow Fixes
   → Agent: deployment-engineer ✨ Learned from previous correction
   → Confidence: 95%
   → Standards: global/*, global/conventions.md

2. Frontend Dashboard Component
   → Agent: frontend-developer
   → Confidence: 88%
   → Standards: global/*, frontend/*

3. Generic Refactoring Task
   → Agent: implementer ⚠️ Low confidence - please confirm
   → Confidence: 62%
   → Standards: global/*, backend/*, frontend/*, testing/*

Proceed? (yes/no/manual/change [number])
```

**User Response Handling:**
- `yes`: Use all auto-assignments, save confirmations to history
- `no`: Fall back to generic implementer for all task groups
- `manual`: Switch to `/orchestrate-tasks` for full manual control
- `change 3`: Prompt user for agent for task group #3, save correction to history

**Saving to History:**
After user responds:
1. If user changed any assignments: Save pattern + correction
2. If user confirmed low-confidence (<70%): Save as confirmation
3. Update statistics (total, confirmed, corrected, accuracy)
4. Write updated history back to `agent-os/data/assignment-history.yml`

## Configuration

See `agent-os/config/auto-assignment-config.yml` for:
- Keyword definitions
- Confidence thresholds
- Learning settings
- Enable/disable flags

## Benefits

1. **Automatic Specialization**: Routes tasks to best-suited agents
2. **Learning Over Time**: Gets smarter from your corrections
3. **Transparency**: Shows confidence scores and reasoning
4. **Flexible**: Easy override when needed
5. **Configurable**: Adjust thresholds and keywords to your needs

## Limitations

- Requires clear task group names/descriptions for best results
- Learning requires history to build up
- Multi-domain tasks may have lower confidence
- Cannot detect context outside of task text (e.g., codebase-specific patterns)

## Troubleshooting

**Low accuracy?**
- Review and refine keywords in config
- Check that task groups have descriptive names
- Manually correct assignments to build learning history

**Wrong agent assigned?**
- Correct manually and system will learn
- Check keyword definitions for conflicts
- Consider if task is truly multi-domain

**Want to reset learning?**
- Delete or rename `agent-os/data/assignment-history.yml`
- System will start fresh

**Disable auto-assignment?**
- Set `enabled: false` in `agent-os/config/auto-assignment-config.yml`
- Falls back to generic implementer

**Disable learning?**
- Set `learning.enabled: false` in config
- System uses static keyword matching only
