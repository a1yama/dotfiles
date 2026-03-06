# fix -- Review Fix Instruction Template

> **Purpose**: Fix issues identified by reviewers
> **Agent**: coder
> **Variations**: General fix / Supervise fix

---

## Template (General fix)

```
Address the reviewer feedback.
Check the session conversation history and fix the issues raised by reviewers.

{Customize: Add report references for multiple reviews}
**Review the review results:**
- AI Review: {report:ai-review.md}
- Architecture Review: {report:architecture-review.md}

{Customize: For multiple reviews}
**Important:** Fix ALL issues from ALL reviews without omission.

**Required output (include headings)**
## Work results
- {Summary of work performed}
## Changes made
- {Summary of changes}
## Test results
- {Command and results}
## Evidence
- {List of verified files/searches/diffs/logs}
```

---

## Template (Supervise fix)

```
Fix the issues raised by the supervisor.

The supervisor identified problems from a holistic perspective.
Address items in order of priority.

**Required output (include headings)**
## Work results
- {Summary of work performed}
## Changes made
- {Summary of changes}
## Test results
- {Command and results}
## Evidence
- {List of verified files/searches/diffs/logs}
```

---

## Unified required output sections

All fix-type movements require these 4 output sections:

| Section | Purpose |
|---------|---------|
| Work results | Summary of what was done |
| Changes made | Specific changes |
| Test results | Verification results |
| Evidence | Verified facts (files, searches, diffs) |

---

## Typical rules

```yaml
# General fix
rules:
  - condition: Fixes completed
    next: reviewers
  - condition: Cannot determine, insufficient information
    next: plan

# Supervise fix
rules:
  - condition: Supervisor's issues have been fixed
    next: supervise
  - condition: Cannot proceed with fixes
    next: plan
```
