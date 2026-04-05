# grumpy_context

`grumpy_context` analyzes a Dart or Flutter project and returns typed context data that bricks and custom lints can consume.

## What it returns

- Project name from `pubspec.yaml`
- Direct dependency declarations grouped by scope
- Discovered modules and their layer inventories
- Diagnostics for missing, partial, or ambiguous structure
- The resolved discovery config that was applied

## Usage

```dart
import 'package:grumpy_context/grumpy_context.dart';

Future<void> main() async {
  final context = await analyzeProject('/path/to/project');

  print(context.name);
  print(context.modules.map((module) => module.name).toList());
}
```

## `grumpy.yaml`

The analyzer looks for an optional root-level `grumpy.yaml`. If it is missing, built-in defaults are used.

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/necodeIT/grumpy_context/refs/heads/main/grumpy.schema.json
module_roots:
  - lib
  - lib/src

layers:
  utils:
    - utils
  domain:
    models:
      - domain/models
    services:
      - domain/services
    datasources:
      - domain/datasources
  infra:
    services:
      - infra/services
    datasources:
      - infra/datasources
  presentation:
    components:
      - presentation/components
    screens:
      - presentation/screens
    repos:
      - presentation/repos
    middleware:
      - presentation/middleware
      - presentation/guards
```

The output schema is fixed. `grumpy.yaml` only changes how the project is discovered.

## Logging

The package emits structured logs through `package:logging` using logger names under `grumpy_context.*`, for example:

- `grumpy_context.analyzer`
- `grumpy_context.config`
- `grumpy_context.pubspec`
- `grumpy_context.scanner`
- `grumpy_context.diagnostics`

No log handlers are installed by default.

## Schema

A JSON schema for `grumpy.yaml` is provided at [grumpy.schema.json](grumpy.schema.json).
