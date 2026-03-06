# ai-review-standalone -- AI Review (Standalone) Instruction Template

> **Purpose**: Specialized review of AI-generated code (runs as an independent movement with iteration tracking)
> **Agent**: ai-antipattern-reviewer
> **For parallel sub-step use, see variation B in `review.md`**

---

## Template

```
**This is AI Review round {movement_iteration}.**

On the first round, review comprehensively and report all issues.
On round 2 and later, prioritize verifying whether previously REJECTed items have been fixed.

Review the code for AI-specific issues:
- Assumption verification
- Plausible but incorrect patterns
- Compatibility with the existing codebase
- Scope creep detection
```

---

## Differences from parallel sub-step

| | standalone | parallel sub-step |
|--|-----------|-------------------|
| Iteration tracking | Yes (`{movement_iteration}`) | No |
| First/subsequent instruction branching | Yes | No |
| Next movement | ai_fix or reviewers | Parent movement decides |

Standalone is for pieces that form an ai_review -> ai_fix loop.
Parallel sub-steps use variation B from review.md.

---

## Typical rules

```yaml
rules:
  - condition: No AI-specific issues
    next: reviewers
  - condition: AI-specific issues found
    next: ai_fix
```
