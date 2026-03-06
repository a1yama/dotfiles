# ai-fix -- AI Issue Fix Instruction Template

> **Purpose**: Fix issues identified by AI Review
> **Agent**: coder
> **Feature**: Built-in countermeasures against the "already fixed" false recognition bug

---

## Template

```
**This is AI Review round {movement_iteration}.**

If this is round 2 or later, the previous fixes were NOT actually applied.
**Your belief that they were "already fixed" is wrong.**

**First, acknowledge:**
- The files you thought were "fixed" were NOT actually modified
- Your memory of the previous work is incorrect
- You need to rethink from scratch

**Required actions:**
1. Open ALL flagged files with the Read tool (abandon assumptions, verify facts)
2. Search for the problem locations with grep to confirm they exist
3. Fix confirmed issues with the Edit tool
4. Run tests to verify
5. Report specifically "what you verified and what you fixed"

**Report format:**
- NG: "Already fixed"
- OK: "Checked file X at L123, found issue Y, fixed by changing to Z"

**Strictly prohibited:**
- Reporting "already fixed" without opening the file
- Making assumptions without verification
- Ignoring issues that the AI Reviewer REJECTed

**Handling "no fix needed" (required)**
- Do not judge "no fix needed" unless you can show verification results for the target file of each issue
- If the issue relates to "generated artifacts" or "spec synchronization", output the tag corresponding to "cannot determine" if you cannot verify the source/spec
- If no fix is needed, output the tag corresponding to "cannot determine" and clearly state the reason and verification scope

**Required output (include headings)**
## Files checked
- {file_path:line_number}
## Searches performed
- {command and summary}
## Fix details
- {changes made}
## Test results
- {command and results}
```

---

## Typical rules

```yaml
rules:
  - condition: AI issue fixes completed
    next: ai_review
  - condition: No fix needed (target files/specs verified)
    next: ai_no_fix
  - condition: Cannot determine, insufficient information
    next: ai_no_fix
```

---

## Notes

Use this template as-is across all pieces. There are no customization points.
The bug where AI falsely believes fixes were "already applied" is a model-wide issue;
modifying or omitting the countermeasure text directly degrades quality.
