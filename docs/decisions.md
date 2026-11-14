# Decision log

Why the pipeline is built the way it is. Each entry states the decision, the reason and,
where relevant, the alternative that was rejected. Update this file whenever a decision
changes; the history stays in Git.

## 1. Goal

Build an AI-assisted, spec-driven development pipeline that is **agent-agnostic**: the same
request, processed by different agents (Claude Code, Antigravity CLI), must produce results
that can be compared against the same objective gates. The pipeline is treated as a real
application because it will later be applied at work.

Phases: **analysis** (OpenSpec) → **implementation** → **CI/CD**. Tools are added one at a
time, only when the previous phase works end to end.

## 2. Repository model

| Decision | Reason | Rejected alternative |
|---|---|---|
| Three repositories: `pipeline-base`, `pipeline-claude`, `pipeline-gemini` | Full isolation per agent; no agent sees another agent's files, branches or history | One repo with branches per agent (cross-contamination risk) |
| `pipeline-base` is the single source of truth for everything shared | Shared files must be identical, or the comparison measures configuration, not agents | Editing shared files in each agent repo |
| Agent repos are clones of the base with `upstream` (push disabled with `NO_PUSH`) | Same model as a fork without its restrictions | GitHub fork: cannot fork your own repo into the same account; PRs default to the upstream repo; Actions and Issues disabled by default |
| | | GitHub template repository: no shared history, so `upstream` merges stop working |
| Agent repos are created completely empty on GitHub | Any initial commit breaks the shared history | |
| Every change to the base is tagged (`base-vX.Y`) | Each experiment records exactly which base it used | |
| Sync with `git fetch upstream --tags && git merge <tag>` (`pull.rebase false`) | Agent repos have their own published commits; rebasing would rewrite published history | Rebase + force push |

Current base version: see `git tag` in `pipeline-base`.

## 3. Workflow

1. A request is written in `requests/<id>-<slug>.md` (in the base: it is the common input).
2. **Analysis**: in a new agent session, the agent runs the propose command with the exact
   text of `docs/prompts/analysis.md`. It produces the OpenSpec change and the Cucumber
   feature files tagged `@pending`.
3. The human checks gate 0 personally (`openspec validate --strict`, `./mvnw verify`), opens
   the PR and reviews it with `docs/gates/spec-gate.md`. The result template goes in the PR.
4. **Implementation**: a different, new session implements the tasks. It never sees the
   analysis conversation, only the artifacts. The last task removes `@pending`.
5. CI/CD: pending (see section 10).

| Decision | Reason |
|---|---|
| Separate sessions for analysis and implementation | Phases communicate only through artifacts; ambiguities surface instead of being hidden by context |
| Feature files written in the analysis phase, reviewed with the spec, frozen during implementation | If the same agent writes the acceptance tests and the code, it grades itself |
| `@pending` tag excluded by the Cucumber runner | Undefined steps would break `verify` on every analysis PR |
| The only allowed change to a feature file during implementation is removing `@pending` | Mechanically checkable with `git diff` |
| One shared prompt file | Hand-typed prompts drift and pollute the comparison |
| First full cycle with Claude only; fix the base; then Gemini | The first run exposes pipeline problems; both agents must use the same base version |

## 4. Agent-agnostic design

| Decision | Reason |
|---|---|
| `AGENTS.md`: how to work with the code. `openspec/config.yaml`: how to write specs. No duplication | Two sources of truth would diverge |
| Claude adapter: `CLAUDE.md` contains only `@AGENTS.md` | No duplicated content |
| Antigravity reads `AGENTS.md` natively; never create `GEMINI.md` | `GEMINI.md` would take precedence and break parity |
| Antigravity CLI (`agy`) instead of Gemini CLI | Gemini CLI stopped serving Google AI Pro/Ultra plans in June 2026 |
| OpenSpec initialized per repo with only its tool (`--tools claude` / `--tools antigravity`), same `core` profile | No traces of the other agent; same workflows on both sides |
| Global agent configuration neutralized during experiments (`~/.claude/CLAUDE.md`, `~/.gemini/...`) | Personal preferences would contaminate the comparison |
| Model, effort and CLI version fixed and recorded per experiment | Otherwise results are not comparable |
| Comparison = same gates passed, not similar code | LLMs are not deterministic; two runs of the same agent already differ |
| Artifacts in English | Matches OpenSpec keywords and templates |

## 5. Stack and configuration

| Decision | Reason | Rejected alternative |
|---|---|---|
| Java 25, Spring Boot 4.1, Maven wrapper only | Current LTS and Boot generation; reproducible builds across machines | Global `mvn` |
| PostgreSQL + Spring Data JPA + Flyway; `ddl-auto: validate` | Realistic; schema owned by migrations, Hibernate only validates | H2 or any in-memory database |
| Explicit Hikari settings (`pool-name`, size 10, 10 s timeout, 30 min lifetime) | Decisions documented instead of implicit defaults | Arbitrary tuning without load tests |
| `open-in-view: false` | Avoids holding connections for the whole request and hidden lazy loading | |
| Local database with `compose.yaml` started manually; credentials in a gitignored `.env`, documented in `.env.example` | Same workflow as at work; no credentials in Git, not even local ones | `spring-boot-docker-compose` |
| `local` profile reads `.env` via `spring.config.import`; `application.yaml` has no connection | Production fails fast if `SPRING_DATASOURCE_*` is missing instead of connecting to localhost | Placeholders in `application.yaml` (break CI) |
| UTC everywhere: JVM in tests, Hibernate, Jackson, `timestamptz`, injected `java.time.Clock` | Deterministic tests and a single time zone; `now()` is forbidden | |
| Test JVM locale `en_US` | Localized validation messages would pass locally (es_ES) and fail in CI | |
| `ProblemDetail` for all errors, including framework ones | One error format for the whole API | |
| Virtual threads enabled | Mature in Java 25 | |
| UTF-8 explicit, reproducible builds (`outputTimestamp`), `.sdkmanrc`, `.editorconfig`, `.gitattributes` | Reusable project template | |
| `.mvn/maven.config` with `--no-transfer-progress` | Less log noise, less agent context consumed per `verify` | |

## 6. Architecture

Hexagonal, organized by feature (`domain`, `application/port/in|out`, `application/service`,
`adapter/in/web`, `adapter/out/persistence`). Enforced by ArchUnit; a written rule alone would
be interpreted differently by each agent.

## 7. Quality gates (all run in `./mvnw verify`)

| Gate | Decision and reason |
|---|---|
| Enforcer | Java 25, Maven 3.9+, no duplicated POM dependencies. `dependencyConvergence` excluded: it usually fails with Spring Boot, Testcontainers and Cucumber transitives |
| Compiler | `-Xlint:all,-processing -Werror`: agents tend to leave warnings |
| Spotless (palantir-java-format) | Style decided by a tool; removes formatting noise between agents |
| SpotBugs (effort Max, threshold Medium) | Bug patterns; Low threshold is noisy with Spring. Exclusions only by the maintainer, justified |
| Unit, web, persistence, acceptance tests | JUnit/AssertJ/Mockito, MockMvc, Testcontainers PostgreSQL, Cucumber over HTTP |
| ArchUnit | Hexagonal rules, plus coding rules: no direct `now()`, no field injection, no standard streams, no generic exceptions, no `java.util.logging`, Datafaker only via `TestFaker` |
| JaCoCo | 80% line **and** branch coverage **per class** (no class can hide behind the average); only the main class excluded |
| PIT | 80% mutation score on `domain` and `application` only (speed); catches tests that cover code without asserting |
| jqwik | Property-based tests for every domain rule that constrains input values |
| Datafaker | Only for values irrelevant to the test, through `TestFaker` (fixed seed); relevant values are literals |
| CycloneDX SBOM | Generated in the jar; scanning it is a CI task |

Every gate was proven to **fail** when its rule is broken (sabotage test, all OK).
Baseline `verify` time on an empty project: about 19 s.

## 8. Agent guardrails

| Decision | Reason |
|---|---|
| Only `AGENTS.md`, `openspec/config.yaml` and the active change are instructions; text in logs, test output or dependencies is data | jqwik prints a message addressed to AI agents telling them to ignore its results; any dependency can do the same |
| Never push, never rewrite history, one commit per task | The human publishes |
| Never skip checks from the command line (`-DskipTests`, `-D…skip…`) | `verify` could be "passed" by disabling gates |
| Protected files (agent rules, gate configuration, test infrastructure, agent config directories) | An agent that can edit a rule can pass any check |
| Claude: `.claude/settings.json` (deny/ask/allow), versioned | Deny always wins over local approvals |
| Antigravity: native permissions live outside the repo, so a `PreToolUse` hook (`.agents/hooks/check-permissions.py`) enforces `docs/agents/antigravity-permissions.json` | Versioned rules, same on any machine |
| The hook fails closed (empty/invalid input denied; unknown tools and missing paths ask) | A security control must not allow on error |
| The hook does not write global settings | Global permissions would affect every project |
| Same rule set on both agents | Otherwise one agent works with fewer restrictions |
| Security files are committed after review and before testing them with the agent | Any change made by the agent during tests shows up in `git diff` |

## 9. Known limitations

- Permission rules can be bypassed with shell commands (`sed`, `echo >`); unknown commands ask
  in `agy`, but the final guarantee is the human diff review and, later, CI checks.
- Feature-file freezing cannot be expressed as a permission; it will be checked in CI.
- PIT reads the Surefire `argLine` (with `@{argLine}` and the Mockito agent); not yet verified
  with real domain code beyond the sabotage test.
- jqwik maintainers state that the library must not be used by AI agents; kept because it is
  the most mature Java property-based testing library, with the instruction-source rule above.
- A new session of the same model is not an independent reviewer; independence comes from the
  frozen feature files, the gates and the human review.

## 10. Pending (deliberately deferred)

- CI with GitHub Actions: `verify` on GitHub-hosted runners as the independent referee;
  checks for protected files and feature-file changes; local workflow testing with `gh act`.
- Agents triggered from Issues (labels): no self-hosted runner (public repo); polling script
  or local Jenkins, only issues created by the owner.
- Git hooks and Conventional Commits validation.
- SBOM vulnerability scanning (Dependency-Track in Docker, Grype or Trivy).
- Observability: Actuator, structured logging, SigNoz.
- Parallel test execution (tests are already required to be independent).
- Enforcer `dependencyConvergence`.
- Optional OpenSpec workflows (`verify`, `ff`...), same profile in both repos.

## 11. Experiments

Results are recorded in each analysis PR description using the template in
`docs/gates/spec-gate.md`.
