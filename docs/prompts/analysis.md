# Analysis phase prompt

Use this exact text for every agent, in a new session, after the agent's propose command
(`/opsx:propose` or its equivalent). Replace `<request-file>` with the request path.

---

Start the analysis phase for the request in `<request-file>`.

Create an OpenSpec change for it, following `AGENTS.md` and `openspec/config.yaml`.

This is the analysis phase only. Do not write production code, step definitions or any
test other than the feature files that the OpenSpec rules ask for.

When you finish, run `openspec validate <change-id> --strict` and `./mvnw verify`, and
report both results. Do not commit.
