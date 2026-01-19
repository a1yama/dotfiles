#!/bin/bash

# Read JSON input
input=$(cat)

# Save input for debugging
echo "$input" > /tmp/claude-statusline/last.json

# Parse basic info
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
time_str=$(date +%H:%M:%S)
dir_name=$(basename "$cwd")
model=$(echo "$input" | jq -r '.model.display_name // .model.id // "unknown"')
turn=$(echo "$input" | jq -r '.turn // "0"')

# Parse token usage
input_tokens=$(echo "$input" | jq -r '.usage.input_tokens // 0')
output_tokens=$(echo "$input" | jq -r '.usage.output_tokens // 0')
cache_read=$(echo "$input" | jq -r '.usage.cache_read_tokens // 0')
cache_create=$(echo "$input" | jq -r '.usage.cache_creation_tokens // 0')
total_tokens=$((input_tokens + output_tokens))

# Git info
git_info=""
pr_info=""

if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    # Get branch name
    branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)

    # Get file status
    git_status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    modified=$(echo "$git_status" | grep -c "^ M" || true)
    untracked=$(echo "$git_status" | grep -c "^??" || true)
    staged=$(echo "$git_status" | grep -c "^[AMDR]" || true)

    # Build status string
    status_parts=""
    [ $staged -gt 0 ] && status_parts="${status_parts} ++($staged)"
    [ $modified -gt 0 ] && status_parts="${status_parts} !($modified)"
    [ $untracked -gt 0 ] && status_parts="${status_parts} ?($untracked)"

    [ -n "$branch" ] && git_info=" on $branch${status_parts}"

    # Get PR info (with error logging)
    if command -v gh >/dev/null 2>&1 && [ -n "$branch" ]; then
        {
            pr_data=$(gh pr list --head "$branch" --state open --json number 2>&1)
            pr_count=$(echo "$pr_data" | jq 'length' 2>/dev/null || echo '0')

            if [ "$pr_count" -eq 1 ]; then
                pr_number=$(echo "$pr_data" | jq -r '.[0].number')
                pr_info=" PR#${pr_number}●"
            elif [ "$pr_count" -gt 1 ]; then
                pr_info=" PR:${pr_count}●"
            fi
        } 2>/tmp/claude-statusline/pr-error.log
    fi
fi

# Output formatted status line
printf "\033[1;33m%s\033[0m \033[1;36m%s\033[0m%s%s \033[1;35m%s\033[0m \033[1;32mturn:%s\033[0m \033[1;34mtokens:%s\033[0m (in:%s out:%s cache:%s/%s)" \
    "$time_str" \
    "$dir_name" \
    "$git_info" \
    "$pr_info" \
    "$model" \
    "$turn" \
    "$total_tokens" \
    "$input_tokens" \
    "$output_tokens" \
    "$cache_read" \
    "$cache_create"
