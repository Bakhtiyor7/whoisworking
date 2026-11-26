# Contributing

Thank you for helping. This page says what to expect and how a change gets in. To build and run the app, see [docs/development.md](docs/development.md).

## Before you start

- Who's Working has one maintainer. A review can take a few weeks.
- Pull requests are open to anyone. Fixes to the docs and small fixes to the code are welcome directly.
- For anything larger, open an issue first and agree on the change, so nobody writes code that will be declined.
- Questions go to [Discussions](https://github.com/Bakhtiyor7/whoisworking/discussions). Security problems go to private reporting, as [SECURITY.md](SECURITY.md) says.

## How a change is made

The order is spec, then failing test, then code.

1. Add or edit the requirement in [`docs/specs/`](docs/specs/README.md).
2. Write a test that fails without your change, and name it on the requirement's `Tests:` line.
3. Write the code. New behaviour goes into `Sources/AgentCore`, which is where the tests are.
4. Run the four checks. All of them must pass.

```bash
swift test
```

```bash
scripts/check-specs.sh
```

```bash
scripts/check-public.sh --tree-only
```

```bash
scripts/check-docs.sh
```

## Rules that do not bend

- No third-party dependencies.
- The hook script uses only `/bin/sh` and `/usr/bin/nc`, prints nothing, decides nothing and always exits with success ([spec 05](docs/specs/05-ingest-and-hook-script.md)).
- The hook installer never changes or reorders other tools' entries, backs up before every change, changes nothing when run twice, and refuses, changing nothing, a file that is not valid JSON or not in the shape it expects ([spec 06](docs/specs/06-hook-installer.md)).
- No network use beyond the update check, and no telemetry ([What Who's Working does on your Mac](docs/trust.md)).
- Never put real session ids, prompts, home-folder paths or names in a test fixture. Use placeholders.

## Out of scope

Approving or denying anything from the notch. Who's Working shows status; it never answers for an agent.

## AI tools

Help from coding agents is welcome; Who's Working itself is built with them. Say in your pull request which tools you used and for what. You must be able to explain every line you submit.

## Licence

Who's Working is under the [GNU General Public License, version 3 only](LICENSE) (`GPL-3.0-only`). By contributing, you agree that your contribution is under the same licence. There is no contributor agreement to sign.

## Code of conduct

Everyone who takes part follows the [code of conduct](CODE_OF_CONDUCT.md).
