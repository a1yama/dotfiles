# plan -- Planning Instruction Template

> **Purpose**: Task analysis, requirements gathering, implementation strategy
> **Agent**: planner, architect-planner
> **Customization points**: Indicated by `{Customize:}`

---

## Template

```
Analyze the task and create an implementation plan.

**Note:** If Previous Response is present, this is a replan;
revise the plan based on its content.

{Customize: Handling unknowns -- add the following when using architect-planner}
**Handling unknowns (important):**
If there are unclear points in the task, investigate by reading the code and resolve them yourself.
Only judge as "unclear" for external factors that cannot be resolved through investigation (e.g., user intent is ambiguous).

**Actions:**
1. Understand the task requirements
2. {Customize: Add related code investigation if needed}
3. Identify the impact scope
4. Decide on the implementation approach
```

---

## Variations

### A. Standard plan (using planner)

Planning only. Design is delegated to the architect movement.

### B. Plan + design (using architect-planner)

For lightweight pieces that omit the architect movement.
Use architect-planner instead of planner to include design decisions in the plan.
Add self-resolution instructions for unknowns.

---

## Typical rules

```yaml
rules:
  - condition: Requirements are clear and implementable
    next: {implement or architect}
  - condition: User is asking a question (not an implementation task)
    next: COMPLETE
  - condition: Requirements are unclear, insufficient information
    next: ABORT
```
