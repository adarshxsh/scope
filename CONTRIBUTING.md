# Contributing to Scope

First off, thank you for considering contributing to Scope! It's people like you that make Scope such a great tool.

## Setup Your Local Environment

1. Fork the repo and create your branch from `main`.
2. Ensure you have the Flutter SDK installed.
3. Run `flutter pub get` in the `scope/` directory to fetch dependencies.
4. If you've modified database schemas, run `dart run build_runner build` to regenerate Drift database files.

## Development Workflow

- **Branch Naming**: Use `feature/your-feature-name`, `bugfix/your-bugfix-name`, etc.
- **Testing**: Ensure any new features are accompanied by tests. Run tests via `flutter test`.
- **Linting**: We enforce a strict zero-lint policy. Run `flutter analyze` and ensure no issues are found before submitting your PR.
- **Ghost AI Changes**: Any changes to the Ghost AI classification logic should be tested in the internal Ghost AI Playground before proposing.

## Pull Request Process

1. Ensure your PR description clearly describes the problem and solution.
2. Link to any relevant issues.
3. Keep PRs as small and focused as possible.
4. A maintainer will review your code. Once approved and CI passes, it will be merged.

## Reporting Bugs

- Check if the bug has already been reported.
- Open a new issue with a clear title and description.
- Provide a minimal reproducible example if possible, along with your device model and Android version.
