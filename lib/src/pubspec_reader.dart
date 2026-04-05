import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'logging.dart';
import 'models.dart';

final class PubspecReadResult {
  const PubspecReadResult({
    required this.name,
    required this.dependencies,
    required this.diagnostics,
  });

  final String name;
  final ProjectDependencies dependencies;
  final List<ProjectDiagnostic> diagnostics;
}

Future<PubspecReadResult> readPubspec(String projectRoot) async {
  final logger = grumpyLogger('pubspec');
  final diagnostics = <ProjectDiagnostic>[];
  final pubspecFile = File(p.join(projectRoot, 'pubspec.yaml'));

  if (!await pubspecFile.exists()) {
    logger.severe('pubspec.yaml not found at ${pubspecFile.path}.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'missing_pubspec',
        severity: DiagnosticSeverity.error,
        message: 'pubspec.yaml was not found.',
        path: 'pubspec.yaml',
      ),
    );
    return PubspecReadResult(
      name: '',
      dependencies: ProjectDependencies.empty,
      diagnostics: diagnostics,
    );
  }

  late final Object? rawYaml;
  try {
    rawYaml = loadYaml(await pubspecFile.readAsString());
  } on YamlException catch (error, stackTrace) {
    logger.severe('Failed to parse pubspec.yaml.', error, stackTrace);
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_pubspec_yaml',
        severity: DiagnosticSeverity.error,
        message: 'Failed to parse pubspec.yaml: ${error.message}',
        path: 'pubspec.yaml',
      ),
    );
    return PubspecReadResult(
      name: '',
      dependencies: ProjectDependencies.empty,
      diagnostics: diagnostics,
    );
  }

  if (rawYaml is! YamlMap) {
    logger.severe('pubspec.yaml root must be a map.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'invalid_pubspec_root',
        severity: DiagnosticSeverity.error,
        message: 'pubspec.yaml must contain a top-level map.',
        path: 'pubspec.yaml',
      ),
    );
    return PubspecReadResult(
      name: '',
      dependencies: ProjectDependencies.empty,
      diagnostics: diagnostics,
    );
  }

  final rawName = rawYaml['name'];
  final name = rawName is String ? rawName : '';
  if (name.isEmpty) {
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'missing_project_name',
        severity: DiagnosticSeverity.error,
        message: 'pubspec.yaml is missing a valid package name.',
        path: 'pubspec.yaml',
      ),
    );
  }

  final dependencies = ProjectDependencies(
    dependencies: _parseDependencyGroup(rawYaml['dependencies']),
    devDependencies: _parseDependencyGroup(rawYaml['dev_dependencies']),
    dependencyOverrides: _parseDependencyGroup(rawYaml['dependency_overrides']),
  );

  logger.info(
    'Parsed pubspec for "$name" with ${dependencies.dependencies.length} runtime dependencies.',
  );

  return PubspecReadResult(
    name: name,
    dependencies: dependencies,
    diagnostics: diagnostics,
  );
}

List<ProjectDependency> _parseDependencyGroup(Object? rawGroup) {
  if (rawGroup is! YamlMap) {
    return const <ProjectDependency>[];
  }

  final dependencies = <ProjectDependency>[];
  for (final entry in rawGroup.entries) {
    if (entry.key is! String) {
      continue;
    }
    dependencies.add(
      _parseDependency(name: entry.key as String, rawSpec: entry.value),
    );
  }

  dependencies.sort((left, right) => left.name.compareTo(right.name));
  return dependencies;
}

ProjectDependency _parseDependency({
  required String name,
  required Object? rawSpec,
}) {
  if (rawSpec is String) {
    return ProjectDependency(
      name: name,
      source: DependencySource.hosted,
      constraint: rawSpec,
    );
  }

  if (rawSpec is YamlMap) {
    final details = _normalizeYamlValue(rawSpec);
    final constraint = details['version'] as String?;
    if (details.containsKey('sdk')) {
      return ProjectDependency(
        name: name,
        source: DependencySource.sdk,
        constraint: constraint,
        details: details,
      );
    }
    if (details.containsKey('git')) {
      return ProjectDependency(
        name: name,
        source: DependencySource.git,
        constraint: constraint,
        details: details,
      );
    }
    if (details.containsKey('path')) {
      return ProjectDependency(
        name: name,
        source: DependencySource.path,
        constraint: constraint,
        details: details,
      );
    }
    if (details.containsKey('hosted') || details.containsKey('version')) {
      return ProjectDependency(
        name: name,
        source: DependencySource.hosted,
        constraint: constraint,
        details: details,
      );
    }
    return ProjectDependency(
      name: name,
      source: DependencySource.unknown,
      constraint: constraint,
      details: details,
    );
  }

  return ProjectDependency(
    name: name,
    source: DependencySource.unknown,
    constraint: null,
    details: rawSpec == null
        ? const <String, Object?>{}
        : <String, Object?>{'value': rawSpec.toString()},
  );
}

Map<String, Object?> _normalizeYamlValue(YamlMap value) {
  final normalized = <String, Object?>{};
  for (final entry in value.entries) {
    normalized[entry.key.toString()] = _normalizeYamlNode(entry.value);
  }
  return normalized;
}

Object? _normalizeYamlNode(Object? value) {
  if (value is YamlMap) {
    return _normalizeYamlValue(value);
  }
  if (value is YamlList) {
    return value.map<Object?>(_normalizeYamlNode).toList(growable: false);
  }
  return value;
}
