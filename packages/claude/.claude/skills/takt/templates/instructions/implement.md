# implement -- Implementation Instruction Template

> **Purpose**: Coding and test execution
> **Agent**: coder
> **Reports**: Scope + Decisions (format embedded in template)

---

## Template

```
{Customize: Adjust based on the source movement}
Implement according to the plan from the plan movement.

**Reports to reference:**
- Plan: {report:plan.md}
{Customize: Add if architect movement exists}
- Design: {report:architecture.md} (if exists)

Only reference files within the Report Directory shown in Piece Context.
Do not search or reference other report directories.

{Customize: Add if architect exists}
**Important:** Do not make design decisions; follow the design determined in the architect movement.
Report any unclear points or need for design changes.

**Important**: Add unit tests alongside implementation.
- Add unit tests for newly created classes/functions
- Update relevant tests when modifying existing code
- Test file placement: follow the project's conventions
- Running tests is mandatory. After implementation, always run tests and verify results

**Scope output contract (create at implementation start):**
```markdown
# Change Scope Declaration

## Task
{One-line task summary}

## Planned Changes
| Type | File |
|------|------|
| Create | `src/example.ts` |
| Modify | `src/routes.ts` |

## Estimated Size
Small / Medium / Large

## Impact Area
- {Affected modules or features}
```

**Decisions output contract (at implementation end, only when decisions were made):**
```markdown
# Decision Log

## 1. {Decision}
- **Background**: {Why the decision was needed}
- **Options considered**: {List of options}
- **Rationale**: {Why this was chosen}
```

**Required output (include headings)**
## Work results
- {Summary of work performed}
## Changes made
- {Summary of changes}
## Test results
- {Command and results}
```

---

## Typical rules

```yaml
rules:
  - condition: Implementation complete
    next: {ai_review or reviewers}
  - condition: Implementation not started (report only)
    next: {ai_review or reviewers}
  - condition: Cannot determine, insufficient information
    next: {ai_review or reviewers}
  - condition: User input needed
    next: implement
    requires_user_input: true
    interactive_only: true
```

---

## Report settings

```yaml
report:
  - Scope: coder-scope.md
  - Decisions: coder-decisions.md
```

**Note**: Do not add sequence numbers to report filenames.
Use `coder-scope.md`, not `02-coder-scope.md`.
Sequence numbers depend on piece structure and hinder template reuse.
