# security-review -- Security Review Report Template

> **Purpose**: Output report for the security review movement
> **Difference from general review template**: Severity field + warnings section

---

## Template

```markdown
# Security Review

## Result: APPROVE / REJECT

## Severity: None / Low / Medium / High / Critical

## Check Results
| Category | Result | Notes |
|----------|--------|-------|
| Injection | Pass | - |
| Authentication/Authorization | Pass | - |
| Data Protection | Pass | - |
| Dependencies | Pass | - |

## Vulnerabilities (if REJECT)
| # | Severity | Type | Location | Fix Suggestion |
|---|----------|------|----------|----------------|
| 1 | High | SQLi | `src/db.ts:42` | Use parameterized queries |

## Warnings (non-blocking)
- {Security recommendations}
```

---

## Cognitive Load Reduction Rules

```
**Cognitive load reduction rules:**
- No issues -> Check table only (10 lines or fewer)
- Warnings only -> + 1-2 line warnings (15 lines or fewer)
- Vulnerabilities found -> + table format (30 lines or fewer)
```
