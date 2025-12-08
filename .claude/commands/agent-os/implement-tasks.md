# Spec Implementation Process

Now that we have a spec and tasks list ready for implementation, we will proceed with implementation of this spec by following this multi-phase process:

PHASE 1: Determine which task group(s) from tasks.md should be implemented
PHASE 1.5: Auto-assign specialized agents to task groups
PHASE 2: Delegate implementation to assigned specialized agents
PHASE 3: After ALL task groups have been implemented, delegate to implementation-verifier to produce the final verification report.

Follow each of these phases and their individual workflows IN SEQUENCE:

## Multi-Phase Process

### PHASE 1: Determine which task group(s) to implement

First, check if the user has already provided instructions about which task group(s) to implement.

**If the user HAS provided instructions:** Proceed to PHASE 1.5 to auto-assign specialized agents to those specified task group(s).

**If the user has NOT provided instructions:**

Read `agent-os/specs/[this-spec]/tasks.md` to review the available task groups, then output the following message to the user and WAIT for their response:

```
Should we proceed with implementation of all task groups in tasks.md?

If not, then please specify which task(s) to implement.
```

### PHASE 1.5: Auto-assign specialized agents to task groups

After determining which task groups to implement, automatically assign the most appropriate specialized agent to each task group using the agent assignment service.

**Step 1: Load Configuration and History**

1. Check if auto-assignment is enabled in `@agent-os/config/auto-assignment-config.yml`
   - If `enabled: false`, skip this phase and use generic implementer for all task groups (go to PHASE 2)
   - If `enabled: true`, proceed with auto-assignment

2. Load assignment history from `@agent-os/data/assignment-history.yml` (if learning is enabled)

**Step 2: Analyze Each Task Group**

For each task group in the implementation queue:

1. Extract task group name and description
2. Identify keywords from the text (refer to `@agent-os/config/auto-assignment-config.yml` for keyword lists)
3. Load learning history for similar patterns
4. Calculate match scores for each agent:
   - Base scoring from keyword matches (primary/secondary capabilities)
   - Apply learning bonuses if similar patterns exist in history
   - Calculate confidence score (0.0-1.0)
5. Select top-scoring agent
6. Determine appropriate standards based on agent type (refer to `@agent-os/services/agent_assignment_service.md`)

**Step 3: Present Auto-Assignment Plan**

Display the auto-assignment plan to the user:

```
Auto-Assignment Plan:

1. [Task Group Name]
   → Agent: [agent-name] [learning-indicator if applicable]
   → Confidence: [score]%
   → Standards: [list of standards]

2. [Task Group Name]
   → Agent: [agent-name] [⚠️ if confidence < 70%]
   → Confidence: [score]%
   → Standards: [list of standards]

[Repeat for all task groups in queue]

Proceed? (yes/no/manual/change [number])
- yes: Use auto-assignments as shown
- no: Use generic implementer for all task groups
- manual: Switch to /orchestrate-tasks for full manual control
- change [number]: Manually specify agent for task group [number]
```

**Learning Indicators:**
- `✨ Learned from previous correction` - When learning bonus applied from past user correction
- `⚠️ Low confidence - please confirm` - When confidence < 70%

**Step 4: Process User Response**

Wait for user response and handle accordingly:

**If user responds "yes":**
- Use all auto-assigned agents
- Save all low-confidence confirmations to assignment history (if learning enabled)
- Update learning statistics
- Proceed to PHASE 2 with assigned agents

**If user responds "no":**
- Discard auto-assignments
- Use generic implementer for all task groups
- Proceed to PHASE 2 with implementer

**If user responds "manual":**
- Stop current workflow
- Redirect user to run `/orchestrate-tasks` instead
- Explain that `/orchestrate-tasks` provides full manual control over agent assignment

**If user responds "change [number]":**
- Prompt: "Which agent should handle task group [number]? Available agents: [list]"
- Accept user's agent choice
- Save correction to assignment history (if learning enabled)
- Update confidence for that task group to 1.0 (user-specified)
- Ask again: "Proceed with updated assignments? (yes/no/manual)"
- Allow multiple "change" commands until user says "yes", "no", or "manual"

**Step 5: Update Learning History**

If learning is enabled (`learning.enabled: true` in config):

1. For each task group where user changed assignment:
   ```yaml
   - task_pattern: "[task group name]"
     keywords: [extracted, keywords]
     complexity: [simple|medium|complex]
     auto_assigned: [originally assigned agent]
     user_corrected: [user's choice]
     timestamp: [current timestamp]
   ```

2. For each low-confidence assignment user confirmed:
   ```yaml
   - task_pattern: "[task group name]"
     keywords: [extracted, keywords]
     complexity: [simple|medium|complex]
     auto_assigned: [assigned agent]
     user_confirmed: [assigned agent]
     confidence_was: [confidence score]
     timestamp: [current timestamp]
   ```

3. Update statistics:
   - Increment `total_assignments` by number of task groups
   - Increment `auto_confirmed` for each "yes" on high-confidence
   - Increment `user_corrected` for each manual change
   - Recalculate `accuracy` = (auto_confirmed / total_assignments) * 100
   - Set `last_updated` to current timestamp

4. Write updated history back to `agent-os/data/assignment-history.yml`

### PHASE 2: Delegate implementation to assigned specialized agents

Delegate to the **assigned specialized agent(s)** to implement the specified task group(s):

**For each task group**, delegate to its assigned specialized agent:

Provide to the subagent:
- The specific task group from `agent-os/specs/[this-spec]/tasks.md` including the parent task, all sub-tasks, and any sub-bullet points
- The path to this spec's documentation: `agent-os/specs/[this-spec]/spec.md`
- The path to this spec's requirements: `agent-os/specs/[this-spec]/planning/requirements.md`
- The path to this spec's visuals (if any): `agent-os/specs/[this-spec]/planning/visuals`
- The assigned standards for this agent (as determined in Phase 1.5)

Instruct the subagent to:
1. Analyze the provided spec.md, requirements.md, and visuals (if any)
2. Analyze patterns in the codebase according to its built-in workflow
3. Implement the assigned task group according to requirements and assigned standards
4. Update `agent-os/specs/[this-spec]/tasks.md` to mark completed tasks with `- [x]`

**Note:** If multiple task groups were assigned to the same specialized agent, you may delegate them together in a single call for efficiency. If different agents were assigned, delegate each task group separately to its respective agent.

### PHASE 3: Produce the final verification report

IF ALL task groups in tasks.md are marked complete with `- [x]`, then proceed with this step.  Otherwise, return to PHASE 1.

Assuming all tasks are marked complete, then delegate to the **implementation-verifier** subagent to do its implementation verification and produce its final verification report.

Provide to the subagent the following:
- The path to this spec: `agent-os/specs/[this-spec]`
Instruct the subagent to do the following:
  1. Run all of its final verifications according to its built-in workflow
  2. Produce the final verification report in `agent-os/specs/[this-spec]/verifications/final-verification.md`.
