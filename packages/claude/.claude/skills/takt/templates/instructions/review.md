# review -- Review Instruction Template

> **Purpose**: Review within parallel sub-steps (general purpose)
> **Agent**: architecture-reviewer, qa-reviewer, security-reviewer, frontend-reviewer, ai-antipattern-reviewer, etc.
> **Feature**: Personas carry domain knowledge, so instructions can be minimal

---

## Template (Basic form)

```
{Customize: One sentence describing the review focus}
Focus on **{review name}** review.
{Customize: Add exclusions if applicable}
Do not review AI-specific issues (handled in the ai_review movement).

{Customize: Add if reference reports exist}
**Reports to reference:**
- Plan: {report:plan.md}
- Implementation scope: {report:coder-scope.md}

**Review aspects:**
{Customize: Aspect list based on persona expertise}
- {Aspect 1}
- {Aspect 2}
- {Aspect 3}
```

---

## Variations

### A. Architecture review

```
Focus on **architecture and design** review.
Do not review AI-specific issues (handled in the ai_review movement).

**Reports to reference:**
- Plan: {report:plan.md}
- Implementation scope: {report:coder-scope.md}

**Review aspects:**
- Consistency with plan/design
- Code quality
- Appropriateness of change scope
- Test coverage
- Dead code
- Call chain verification
```

### B. AI review (parallel sub-step)

```
Review the code for AI-specific issues:
- Assumption verification
- Plausible but incorrect patterns
- Compatibility with the existing codebase
- Scope creep detection
```

### C. Security review

```
Review changes from a security perspective. Check for these vulnerabilities:
- Injection attacks (SQL, command, XSS)
- Authentication/authorization flaws
- Data exposure risks
- Cryptographic weaknesses
```

### D. QA review

```
Review changes from a quality assurance perspective.

**Review aspects:**
- Test coverage and quality
- Testing strategy (unit/integration/E2E)
- Error handling
- Logging and monitoring
- Maintainability
```

---

## Design principles

- **Keep instructions minimal**: Personas carry domain expertise, so instructions only specify the review target and focus
- **Aspect lists may overlap with persona**: The instruction's aspect list serves as a reminder to the agent
- **State exclusions explicitly**: Use instructions to define responsibility boundaries between reviewers

---

## Typical rules

```yaml
rules:
  - condition: approved
  - condition: needs_fix
```
