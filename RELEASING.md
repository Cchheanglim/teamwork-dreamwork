# Releasing

The skill and the plugin are released separately from this repo. Each has its own version, git tag and GitHub release. Both are built from `skills/teamwork-dreamwork/`. Run the commands in Git Bash (or any bash) from the repo root, after the release commit is pushed.

## Skill

The version lives only in the tag, `skill-v<version>`.

```bash
V=1.0.0
git tag -a "skill-v$V" -m "teamwork-dreamwork skill $V"
git push origin "skill-v$V"
git archive --format=zip --prefix=teamwork-dreamwork/ -o "teamwork-dreamwork-skill-v$V.zip" "skill-v$V:skills/teamwork-dreamwork"
```

On GitHub: **Releases → Draft a new release**, pick tag `skill-v$V`, title `Skill v$V`, attach the zip, publish. Unzipping it into `~/.claude/skills/` gives `~/.claude/skills/teamwork-dreamwork/`. Don't commit the zip.

## Plugin

The version lives in `.claude-plugin/plugin.json`. Plugin users install from the default branch, so bump `version` there when you want them to get an update, then commit and push.

```bash
claude plugin tag --push .
```

This checks that `plugin.json` and `marketplace.json` agree, then creates and pushes the tag `teamwork-dreamwork--v<version>`. On GitHub, draft a release from that tag, titled `Plugin v<version>`. There is nothing to attach: users install with `/plugin install teamwork-dreamwork --marketplace Cchheanglim/teamwork-dreamwork`.

## Which one shows as "Latest"

GitHub marks the newest release as **Latest**, whichever track it is. When you publish, untick **Set as the latest release** if you want the other one to stay on top.
