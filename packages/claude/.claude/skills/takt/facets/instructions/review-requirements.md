Review the changes from a requirements fulfillment perspective.

**Review criteria:**
- Whether each requested requirement has been implemented
- Whether implicit requirements (naturally expected behaviors) are satisfied
- Whether changes outside the scope (scope creep) have crept in
- Whether there are any partial or missing implementations


**Design decisions reference:**
Review {report:coder-decisions.md} to understand the recorded design decisions.
- Do not flag intentionally documented decisions as FP
- However, also evaluate whether the design decisions themselves are sound, and flag any problems

**Previous finding tracking (required):**
- First, extract open findings from "Previous Response"
- Assign `finding_id` to each finding and classify current status as `new / persists / resolved`
- If status is `persists`, provide concrete unresolved evidence (file/line)

## Judgment Procedure

1. Extract requirements one by one from the review target report and task
2. For each requirement, identify the implementing code (file:line)
3. Confirm that the code satisfies the requirement
4. Check for any changes not covered by the requirements
5. For each detected issue, classify as blocking/non-blocking based on Policy's scope determination table and judgment rules
6. If there is even one blocking issue (`new` or `persists`), judge as REJECT
