# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Agent `model`). Alias entries in a panel list still count toward its fan-out.
# budget: medium (high)
# Claude Code has no grok or composer slugs, so those roles run on the parent model; prose and judgment use `sonnet high` instead of the default `opus xhigh`.
feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: sonnet high
hardest tasks: sonnet high
how explorer: inherit-parent
how explainer: sonnet high
why investigators: inherit-parent
why synthesizer: sonnet high
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: sonnet high
arena runners: sonnet high, inherit-parent
arena cross-judge pool: sonnet high, inherit-parent
swarm workers: inherit-parent
architect runners: sonnet high, inherit-parent
interrogate reviewers: sonnet high, inherit-parent
