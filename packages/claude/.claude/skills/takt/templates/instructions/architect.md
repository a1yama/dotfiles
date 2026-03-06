# architect -- Architecture Design Instruction Template

> **Purpose**: Architecture design (make design decisions based on the plan report)
> **Agent**: architect
> **Prerequisite**: Runs after the plan movement

---

## Template

```
Read the plan report ({report:plan.md}) and perform the architecture design.

**Criteria for small tasks:**
- Only 1-2 file changes
- No design decisions needed
- No technology selection needed

For small tasks, skip the design report and
match the rule for "Small task (no design needed)".

**Tasks requiring design:**
- 3 or more file changes
- Adding new modules or features
- Technology selection required
- Architecture pattern decisions needed

**Actions:**
1. Evaluate the task scope
2. Determine file structure
3. Technology selection (if needed)
4. Choose design patterns
5. Create implementation guidelines for the Coder
```

---

## Typical rules

```yaml
rules:
  - condition: Small task (no design needed)
    next: implement
  - condition: Design complete
    next: implement
  - condition: Insufficient information, cannot determine
    next: ABORT
```
