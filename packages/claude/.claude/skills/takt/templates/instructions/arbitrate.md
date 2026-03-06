# arbitrate -- Arbitration Instruction Template

> **Purpose**: Arbitrate when the reviewer and coder disagree
> **Agent**: architecture-reviewer (as a neutral third party)
> **Prerequisite**: ai_fix judged "no fix needed" -> resolve the contradiction with the reviewer's findings

---

## Template

```
ai_review (reviewer) and ai_fix (coder) disagree.

- ai_review identified issues and REJECTed
- ai_fix verified and judged "no fix needed"

Review both outputs and arbitrate which judgment is valid.

**Reports to review:**
- AI review results: {report:ai-review.md}

**Judgment criteria:**
- Are ai_review's findings specific and pointing to real issues in the code?
- Does ai_fix's rebuttal have evidence (file verification results, test results)?
- Are the findings non-blocking (record only) level, or do they actually require fixes?
```

---

## Typical rules

```yaml
rules:
  - condition: ai_review's findings are valid (should be fixed)
    next: ai_fix
  - condition: ai_fix's judgment is valid (no fix needed)
    next: reviewers
```

---

## Notes

- Change the report reference filename according to the piece
- Use a third party for arbitration, not the reviewer or coder themselves
