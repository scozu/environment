---
description: Commit and push the current worktree
agent: build
---
Use the current conversation context, including any recent `/review` results, to commit and push the current task.

Requirements:
- Operate on the whole git working tree, including staged, unstaged, and relevant untracked files.
- Follow the global OpenCode rules for bun usage, git safety, and commit message quality.
- Start by checking `git status`, `git diff`, and recent commits to understand what will be committed and how this repo writes commit messages.
- Check whether the current branch already tracks a remote branch before pushing.
- Stage the relevant changes for the current task.
- If `$ARGUMENTS` is present, treat it as the user's intent or preferred commit message and normalize it to the commit message rules.
- Create a durable commit message that explains intent and impact.
- Push the current branch with a normal push. If the branch has no upstream, set it with `-u`.
- Never force push, never bypass hooks, and never create an empty commit.
- If unrelated changes are mixed into the worktree, call that out and use best judgment about whether they belong in this commit.
