# validation -- Final Verification Report Template

> **Purpose**: Validation report for the supervise movement
> **Report setting**: `Validation: supervisor-validation.md`

---

## Template

```markdown
# Final Verification Results

## Result: APPROVE / REJECT

## Verification Summary
| Item | Status | Verification Method |
|------|--------|-------------------|
| Requirements met | Pass | Compared against requirements list |
| Tests | Pass | `npm test` (N passed) |
| Build | Pass | `npm run build` succeeded |
| Functional check | Pass | Main flow verified |

## Artifacts
- Created: {created files}
- Modified: {modified files}

## Incomplete Items (if REJECT)
| # | Item | Reason |
|---|------|--------|
| 1 | {item} | {reason} |
```
