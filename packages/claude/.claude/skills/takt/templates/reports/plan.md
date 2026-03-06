# plan -- Task Plan Report Template

> **Purpose**: Output report for the plan movement
> **Report setting**: `name: plan.md`

---

## Template (Standard)

```markdown
# Task Plan

## Original Request
{User's request as-is}

## Analysis

### Objective
{What needs to be achieved}

### Scope
{Impact area}

### Implementation Approach
{How to proceed}

## Open Questions (if any)
- {Unclear points or items requiring confirmation}
```

---

## Template (Extended -- when using architect-planner)

For including design decisions in the plan.

```markdown
# Task Plan

## Original Request
{User's request as-is}

## Analysis

### Objective
{What needs to be achieved}

### Scope

**Files to change:**
| File | Changes |
|------|---------|

**Test impact:**
| File | Impact |
|------|--------|

### Design Decisions (if needed)
- File structure: {New file placement, rationale}
- Design pattern: {Pattern adopted and rationale}

### Implementation Approach
{How to proceed}
```

---

## Cognitive Load Reduction Rules

Plan reports have no reduction rules (always output all sections).
