# review -- General Review Report Template

> **Purpose**: Output report for review movements (base form for all review types)
> **Variations**: Architecture / AI / QA / Frontend

---

## Template (Basic form)

```markdown
# {Review Name}

## Result: APPROVE / REJECT

## Summary
{1-2 sentence result summary}

## {Aspect List}
{Customize: Checklist or table format}

## Issues (if REJECT)
| # | {Category column} | Location | Issue | Fix Suggestion |
|---|-------------------|----------|-------|----------------|
| 1 | {Category} | `src/file.ts:42` | Issue description | How to fix |
```

---

## Variations

### A. Architecture Review

```markdown
# Architecture Review

## Result: APPROVE / REJECT

## Summary
{1-2 sentence result summary}

## Aspects Checked
- [x] Structure & design
- [x] Code quality
- [x] Change scope
- [x] Test coverage
- [x] Dead code
- [x] Call chain verification

## Issues (if REJECT)
| # | Scope | Location | Issue | Fix Suggestion |
|---|-------|----------|-------|----------------|
| 1 | In scope | `src/file.ts:42` | Issue description | How to fix |

Scope: "In scope" (fixable in this change) / "Out of scope" (pre-existing, non-blocking)

## Pre-existing Issues (reference, non-blocking)
- {Pre-existing issues unrelated to the current change}
```

### B. AI-Generated Code Review

```markdown
# AI-Generated Code Review

## Result: APPROVE / REJECT

## Summary
{One sentence result summary}

## Items Verified
| Aspect | Result | Notes |
|--------|--------|-------|
| Assumption validity | Pass | - |
| API/library existence | Pass | - |
| Context compatibility | Pass | - |
| Scope | Pass | - |

## Issues (if REJECT)
| # | Category | Location | Issue |
|---|----------|----------|-------|
| 1 | Hallucinated API | `src/file.ts:23` | Non-existent method |
```

### C. QA Review

```markdown
# QA Review

## Result: APPROVE / REJECT

## Summary
{1-2 sentence result summary}

## Aspects Checked
| Aspect | Result | Notes |
|--------|--------|-------|
| Test coverage | Pass | - |
| Test quality | Pass | - |
| Error handling | Pass | - |
| Documentation | Pass | - |
| Maintainability | Pass | - |

## Issues (if REJECT)
| # | Category | Issue | Fix Suggestion |
|---|----------|-------|----------------|
| 1 | Testing | Issue description | How to fix |
```

### D. Frontend Review

```markdown
# Frontend Review

## Result: APPROVE / REJECT

## Summary
{1-2 sentence result summary}

## Aspects Checked
| Aspect | Result | Notes |
|--------|--------|-------|
| Component design | Pass | - |
| State management | Pass | - |
| Performance | Pass | - |
| Accessibility | Pass | - |
| Type safety | Pass | - |

## Issues (if REJECT)
| # | Location | Issue | Fix Suggestion |
|---|----------|-------|----------------|
| 1 | `src/file.tsx:42` | Issue description | How to fix |
```

---

## Cognitive Load Reduction Rules (shared across all variations)

```
**Cognitive load reduction rules:**
- APPROVE + no issues -> Summary only (5 lines or fewer)
- APPROVE + minor suggestions -> Summary + suggestions (15 lines or fewer)
- REJECT -> Issues in table format (30 lines or fewer)
```
