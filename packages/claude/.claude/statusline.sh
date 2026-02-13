#!/bin/bash

# Read JSON input
input=$(cat)

# Save input for debugging
mkdir -p /tmp/claude-statusline
echo "$input" > /tmp/claude-statusline/last.json

# Parse basic info
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
dir_name=$(basename "$cwd")
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')

# Parse token usage
input_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
total_tokens=$((input_tokens + output_tokens))
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' | xargs printf '%.2f')

# ==============================================================
# Line 1: Git status
# ==============================================================
git_line=""

if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)

    # Branch name
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

    # File status
    git_status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    modified=$(echo "$git_status" | grep -c "^ M" || true)
    untracked=$(echo "$git_status" | grep -c "^??" || true)
    staged=$(echo "$git_status" | grep -c "^[AMDR]" || true)

    status_parts=""
    [ "$staged" -gt 0 ] && status_parts="${status_parts} \033[1;32m+($staged)\033[0m"
    [ "$modified" -gt 0 ] && status_parts="${status_parts} \033[1;33m!($modified)\033[0m"
    [ "$untracked" -gt 0 ] && status_parts="${status_parts} \033[1;31m?($untracked)\033[0m"

    # Merge/Rebase state
    state=""
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
        state=" \033[1;31m[REBASING]\033[0m"
    elif [ -f "$git_dir/MERGE_HEAD" ]; then
        state=" \033[1;31m[MERGING]\033[0m"
    elif [ -f "$git_dir/CHERRY_PICK_HEAD" ]; then
        state=" \033[1;33m[CHERRY-PICK]\033[0m"
    elif [ -f "$git_dir/REVERT_HEAD" ]; then
        state=" \033[1;33m[REVERTING]\033[0m"
    fi

    git_line="\033[1;36m${dir_name}\033[0m \033[0;90mon\033[0m \033[1;36m${branch}\033[0m${status_parts}${state}"

    # ==============================================================
    # Line 2: GitHub PR info (only if PR exists)
    # ==============================================================
    if command -v gh >/dev/null 2>&1 && [ -n "$branch" ]; then
        {
            pr_json=$(gh pr list --head "$branch" --state open --json number,url,state,statusCheckRollup,reviewDecision --limit 1 2>/dev/null)
            pr_count=$(echo "$pr_json" | jq 'length' 2>/dev/null || echo '0')

            if [ "$pr_count" -ge 1 ]; then
                pr_number=$(echo "$pr_json" | jq -r '.[0].number')
                pr_url=$(echo "$pr_json" | jq -r '.[0].url')

                # Review status
                review=$(echo "$pr_json" | jq -r '.[0].reviewDecision // ""')
                case "$review" in
                    APPROVED)          review_label="\033[1;32mAPPROVED\033[0m" ;;
                    CHANGES_REQUESTED) review_label="\033[1;31mCHANGES REQUESTED\033[0m" ;;
                    REVIEW_REQUIRED)   review_label="\033[1;33mREVIEW REQUIRED\033[0m" ;;
                    *)                 review_label="\033[0;90mNO REVIEW\033[0m" ;;
                esac

                # CI status (aggregate from statusCheckRollup)
                ci_status=""
                if echo "$pr_json" | jq -e '.[0].statusCheckRollup | length > 0' >/dev/null 2>&1; then
                    ci_fail=$(echo "$pr_json" | jq '[.[0].statusCheckRollup[] | select(.conclusion == "FAILURE" or .conclusion == "ERROR")] | length' 2>/dev/null || echo 0)
                    ci_pending=$(echo "$pr_json" | jq '[.[0].statusCheckRollup[] | select(.status == "IN_PROGRESS" or .status == "QUEUED" or .status == "PENDING")] | length' 2>/dev/null || echo 0)

                    if [ "$ci_fail" -gt 0 ]; then
                        ci_status=" \033[1;31mCI:FAIL\033[0m"
                    elif [ "$ci_pending" -gt 0 ]; then
                        ci_status=" \033[1;33mCI:RUNNING\033[0m"
                    else
                        ci_status=" \033[1;32mCI:PASS\033[0m"
                    fi
                fi

                echo -e "\033[1;35mPR#${pr_number}\033[0m ${pr_url} ${review_label}${ci_status}"
            fi
        } 2>/tmp/claude-statusline/pr-error.log
    fi
else
    git_line="\033[1;36m${dir_name}\033[0m"
fi

echo -e "$git_line"

# ==============================================================
# Line 3: Claude Code info
# ==============================================================
echo -e "\033[1;35m${model}\033[0m \033[1;34mtokens:${total_tokens}\033[0m (in:${input_tokens} out:${output_tokens}) \033[1;32m\$${cost}\033[0m"
