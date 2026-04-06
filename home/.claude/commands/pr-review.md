You are reviewing pull requests.

**Task**: Review the following PRs: {{.Input}}

For each PR number provided (space or comma separated):

1. **Fetch PR information** using `gh pr view <number> --json title,body,author,state,files,createdAt,additions,deletions`

2. **Identify team-owned files** by checking `.github/CODEOWNERS`:
   - **Priority A** (Primary focus): Files owned by your team
   - **Priority B** (Secondary focus): Files owned by related teams
   - **Priority C** (Context only): Other files only as they relate to A/B

3. **Review focus areas** (all of these):
   - **Correctness**: Code logic, API usage, potential bugs
   - **Security**: Security implications, access control, secrets handling
   - **Performance**: Performance implications, scalability concerns
   - **Code quality**: Style, maintainability, error handling
   - **Testing**: Test coverage, test quality
   - **Architecture**: Design patterns, consistency with existing patterns
   - **Breaking changes**: API changes, backward compatibility

4. **Write review to file**: `~/.claude/reviews/{{date}}-PR{{number}}.md` where:
   - `{{date}}` is today's date in format `YYYY-MM-DD`
   - `{{number}}` is the PR number
   - One file per PR

5. **Review format** (markdown):
   ```markdown
   # PR Review: #{{number}} - {{title}}

   **Review Date**: {{date}}
   **PR Author**: {{author}}
   **Status**: APPROVE / CONCERNS / DO NOT MERGE

   ## Executive Summary
   [Brief overview of PR and verdict]

   ## Files Changed
   [List key files changed]

   ## Issues Found
   ### Critical Issues
   [Critical severity issues with file:line references]

   ### High Severity Issues
   [High severity issues with file:line references]

   ### Medium Severity Issues
   [Medium severity issues with file:line references]

   ### Low Severity Issues
   [Low severity issues with file:line references]

   ## Security Review
   [Security assessment]

   ## Performance Review
   [Performance implications]

   ## Architecture Review
   [Architecture and design patterns]

   ## Testing Assessment
   [Test coverage and quality]

   ## Breaking Changes Assessment
   [Backward compatibility analysis]

   ## Questions for PR Author
   [List of clarifying questions]

   ## Recommendations
   ### Must Fix Before Merge
   [Blocking issues]

   ### Should Fix Before Merge
   [High priority non-blocking]

   ### Nice to Have
   [Improvements]

   ## Overall Assessment
   [Final verdict with reasoning]

   ## File References
   [Absolute paths to reviewed files]
   ```

6. **DO NOT post comments on GitHub** - only write to local review files

7. **After completing all reviews**, provide a summary to the user:
   - List of PRs reviewed
   - File location for each review
   - Quick status summary (Approve/Concerns/Block)

**Important Notes**:
- Use the Agent tool with specialized agents to analyze large diffs
- Reference specific file paths and line numbers for all issues
- Classify severity: Critical (blocks merge) / High (should fix) / Medium (nice to fix) / Low (minor) / Info (FYI)
- Be thorough but constructive in feedback
