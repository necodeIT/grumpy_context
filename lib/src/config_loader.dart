import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'logging.dart';
import 'models.dart';

/// The result of loading and validating `grumpy.yaml`.
final class ConfigLoadResult {
  /// Creates a config load result.
  const ConfigLoadResult({
    required this.config,
    required this.diagnostics,
    required this.hasFatalError,
  });

  /// The resolved configuration used for discovery.
  final ResolvedGrumpyConfig config;

  /// Diagnostics emitted while parsing or validating the config file.
  final List<ProjectDiagnostic> diagnostics;

  /// Whether config errors are severe enough to stop module discovery.
  final bool hasFatalError;
}

const _moduleRootsKey = 'module_roots';
const _layersKey = 'layers';
const _barrelFilePatternsKey = 'barrel_file_patterns';
const _defaultsKey = 'defaults';
const _commonDefaultsKey = 'common';
const _supportedDefaultUnits = <String>{
  'module',
  'service',
  'datasource',
  'guard',
  'middleware',
  'screen',
  'component',
  'repository',
  'model',
  'unit',
};

const Map<String, ModuleCategory> _nestedCategoryKeyMap =
    <String, ModuleCategory>{
      'domain.models': ModuleCategory.domainModels,
      'domain.services': ModuleCategory.domainServices,
      'domain.datasources': ModuleCategory.domainDatasources,
      'utils': ModuleCategory.utils,
      'infra.services': ModuleCategory.infraServices,
      'infra.datasources': ModuleCategory.infraDatasources,
      'presentation.components': ModuleCategory.presentationComponents,
      'presentation.screens': ModuleCategory.presentationScreens,
      'presentation.repos': ModuleCategory.presentationRepos,
      'presentation.middleware': ModuleCategory.presentationMiddleware,
    };

/// Loads, validates, and resolves `grumpy.yaml` from [projectRoot].
Future<ConfigLoadResult> loadGrumpyConfig(String projectRoot) async {
  final logger = grumpyLogger('config');
  final diagnostics = <ProjectDiagnostic>[];
  final defaults = ResolvedGrumpyConfig.defaults();
  final configFile = await _resolveConfigFile(projectRoot);
  final configPath = p.basename(configFile.path);

  if (!await configFile.exists()) {
    logger.info('No grumpy.yaml or grumpy.yml found; using defaults.');
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: false,
    );
  }

  logger.info('Loading grumpy config from ${configFile.path}.');

  late final Object? rawYaml;
  try {
    rawYaml = loadYaml(await configFile.readAsString());
  } on YamlException catch (error, stackTrace) {
    logger.severe('Failed to parse $configPath.', error, stackTrace);
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_yaml',
        severity: DiagnosticSeverity.error,
        message: 'Failed to parse $configPath: ${error.message}',
        path: configPath,
      ),
    );
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: true,
    );
  }

  if (rawYaml == null) {
    logger.warning('$configPath is empty; using defaults.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'empty_config',
        severity: DiagnosticSeverity.warning,
        message: '$configPath is empty; using default discovery rules.',
        path: configPath,
      ),
    );
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: false,
    );
  }

  if (rawYaml is! YamlMap) {
    logger.severe('$configPath root must be a map.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_root',
        severity: DiagnosticSeverity.error,
        message: '$configPath must contain a top-level map.',
        path: configPath,
      ),
    );
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: true,
    );
  }

  final moduleRoots = _resolveModuleRoots(
    rawYaml: rawYaml,
    defaults: defaults.moduleRoots,
    diagnostics: diagnostics,
    configPath: configPath,
  );
  final layersResult = _resolveLayers(
    rawYaml: rawYaml,
    defaults: defaults.categoryPaths,
    diagnostics: diagnostics,
    configPath: configPath,
  );
  final barrelFilePatterns = _resolveBarrelFilePatterns(
    rawYaml: rawYaml,
    defaults: defaults.barrelFilePatterns,
    diagnostics: diagnostics,
    configPath: configPath,
  );
  final generationDefaults = _resolveGenerationDefaults(
    rawYaml: rawYaml,
    defaults: defaults.generationDefaults,
    diagnostics: diagnostics,
    configPath: configPath,
  );

  if (layersResult.hasFatalError) {
    logger.severe('$configPath contains fatal layer configuration errors.');
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: true,
    );
  }

  final resolved = ResolvedGrumpyConfig(
    moduleRoots: moduleRoots,
    categoryPaths: layersResult.categoryPaths,
    barrelFilePatterns: barrelFilePatterns,
    generationDefaults: generationDefaults,
  );
  logger.info(
    'Resolved config with ${resolved.moduleRoots.length} module roots and '
    '${resolved.categoryPaths.length} categories.',
  );

  return ConfigLoadResult(
    config: resolved,
    diagnostics: diagnostics,
    hasFatalError: false,
  );
}

List<String> _resolveModuleRoots({
  required YamlMap rawYaml,
  required List<String> defaults,
  required List<ProjectDiagnostic> diagnostics,
  required String configPath,
}) {
  final logger = grumpyLogger('config');
  final rawRoots = rawYaml[_moduleRootsKey];
  if (rawRoots == null) {
    return defaults;
  }

  if (rawRoots is! YamlList) {
    logger.warning('module_roots is not a list; using defaults.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_module_roots',
        severity: DiagnosticSeverity.warning,
        message:
            'module_roots must be a list of non-empty strings; using defaults.',
        path: configPath,
      ),
    );
    return defaults;
  }

  final roots = <String>[];
  for (final item in rawRoots) {
    if (item is! String || item.trim().isEmpty) {
      logger.warning('module_roots contains an invalid entry; using defaults.');
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_module_roots',
          severity: DiagnosticSeverity.warning,
          message:
              'module_roots must only contain non-empty strings; using defaults.',
          path: configPath,
        ),
      );
      return defaults;
    }
    roots.add(p.normalize(item));
  }

  if (roots.isEmpty) {
    logger.warning('module_roots is empty; using defaults.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_module_roots',
        severity: DiagnosticSeverity.warning,
        message: 'module_roots must not be empty; using defaults.',
        path: configPath,
      ),
    );
    return defaults;
  }

  return _orderedUnique(roots);
}

final class _LayerResolutionResult {
  const _LayerResolutionResult({
    required this.categoryPaths,
    required this.hasFatalError,
  });

  final Map<ModuleCategory, List<String>> categoryPaths;
  final bool hasFatalError;
}

_LayerResolutionResult _resolveLayers({
  required YamlMap rawYaml,
  required Map<ModuleCategory, List<String>> defaults,
  required List<ProjectDiagnostic> diagnostics,
  required String configPath,
}) {
  final logger = grumpyLogger('config');
  final rawLayers = rawYaml[_layersKey];
  if (rawLayers == null) {
    return _LayerResolutionResult(
      categoryPaths: _copyCategoryPaths(defaults),
      hasFatalError: false,
    );
  }

  if (rawLayers is! YamlMap) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_layers',
        severity: DiagnosticSeverity.error,
        message: 'layers must be a map in $configPath.',
        path: configPath,
      ),
    );
    return _LayerResolutionResult(
      categoryPaths: _copyCategoryPaths(defaults),
      hasFatalError: true,
    );
  }

  final resolved = _copyCategoryPaths(defaults);

  for (final entry in rawLayers.entries) {
    final layerKey = entry.key;
    if (layerKey is! String) {
      diagnostics.add(
        const ProjectDiagnostic(
          code: 'invalid_config_layer_key',
          severity: DiagnosticSeverity.warning,
          message: 'Ignoring non-string layer key in grumpy.yaml.',
          path: 'grumpy.yaml',
        ),
      );
      continue;
    }

    if (layerKey == 'utils') {
      _resolveUtilsLayer(
        value: entry.value,
        diagnostics: diagnostics,
        resolved: resolved,
        configPath: configPath,
      );
      continue;
    }

    if (layerKey == 'domain' ||
        layerKey == 'infra' ||
        layerKey == 'presentation') {
      _resolveNestedLayer(
        layerKey: layerKey,
        value: entry.value,
        diagnostics: diagnostics,
        resolved: resolved,
        configPath: configPath,
      );
      continue;
    }

    logger.warning('Ignoring unknown layer "$layerKey".');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'unknown_config_layer',
        severity: DiagnosticSeverity.warning,
        message: 'Ignoring unknown layer "$layerKey" in $configPath.',
        path: configPath,
      ),
    );
  }

  return _LayerResolutionResult(categoryPaths: resolved, hasFatalError: false);
}

void _resolveUtilsLayer({
  required Object? value,
  required List<ProjectDiagnostic> diagnostics,
  required Map<ModuleCategory, List<String>> resolved,
  required String configPath,
}) {
  final paths =
      _parsePathList(value) ??
      (value is YamlMap ? _parsePathList(value['paths']) : null);
  if (paths == null || paths.isEmpty) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_layer_paths',
        severity: DiagnosticSeverity.warning,
        message:
            'Layer "utils" must be a list of non-empty strings; using defaults.',
        path: configPath,
      ),
    );
    return;
  }

  resolved[ModuleCategory.utils] = paths;
}

void _resolveNestedLayer({
  required String layerKey,
  required Object? value,
  required List<ProjectDiagnostic> diagnostics,
  required Map<ModuleCategory, List<String>> resolved,
  required String configPath,
}) {
  final logger = grumpyLogger('config');
  if (value is! YamlMap) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_layer',
        severity: DiagnosticSeverity.warning,
        message:
            'Layer "$layerKey" must be a map of path lists; using defaults for this layer.',
        path: configPath,
      ),
    );
    return;
  }

  for (final entry in value.entries) {
    final subKey = entry.key;
    if (subKey is! String) {
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_layer_key',
          severity: DiagnosticSeverity.warning,
          message: 'Ignoring non-string nested layer key in $configPath.',
          path: configPath,
        ),
      );
      continue;
    }

    final compoundKey = '$layerKey.$subKey';
    final category = _nestedCategoryKeyMap[compoundKey];
    if (category == null) {
      logger.warning('Ignoring unknown nested layer "$compoundKey".');
      diagnostics.add(
        ProjectDiagnostic(
          code: 'unknown_config_layer',
          severity: DiagnosticSeverity.warning,
          message:
              'Ignoring unknown nested layer "$compoundKey" in $configPath.',
          path: configPath,
        ),
      );
      continue;
    }

    final paths = _parsePathList(entry.value);
    if (paths == null || paths.isEmpty) {
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_layer_paths',
          severity: DiagnosticSeverity.warning,
          message:
              'Layer "$compoundKey" must contain non-empty string paths; using defaults.',
          path: configPath,
        ),
      );
      continue;
    }

    resolved[category] = paths;
  }
}

List<String>? _parsePathList(Object? value) {
  if (value is! YamlList) {
    return null;
  }

  final paths = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      return null;
    }
    paths.add(p.normalize(item));
  }

  return _orderedUnique(paths);
}

List<String> _resolveBarrelFilePatterns({
  required YamlMap rawYaml,
  required List<String> defaults,
  required List<ProjectDiagnostic> diagnostics,
  required String configPath,
}) {
  final logger = grumpyLogger('config');
  final rawPatterns = rawYaml[_barrelFilePatternsKey];
  if (rawPatterns == null) {
    return defaults;
  }

  if (rawPatterns is! YamlList) {
    logger.warning('barrel_file_patterns is not a list; using defaults.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_barrel_file_patterns',
        severity: DiagnosticSeverity.warning,
        message:
            'barrel_file_patterns must be a list of non-empty strings; using defaults.',
        path: configPath,
      ),
    );
    return defaults;
  }

  final patterns = <String>[];
  for (final item in rawPatterns) {
    if (item is! String || item.trim().isEmpty) {
      logger.warning(
        'barrel_file_patterns contains an invalid entry; using defaults.',
      );
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_barrel_file_patterns',
          severity: DiagnosticSeverity.warning,
          message:
              'barrel_file_patterns must only contain non-empty strings; using defaults.',
          path: configPath,
        ),
      );
      return defaults;
    }
    patterns.add(item);
  }

  if (patterns.isEmpty) {
    logger.warning('barrel_file_patterns is empty; using defaults.');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_barrel_file_patterns',
        severity: DiagnosticSeverity.warning,
        message: 'barrel_file_patterns must not be empty; using defaults.',
        path: configPath,
      ),
    );
    return defaults;
  }

  return _orderedUnique(patterns);
}

GrumpyGenerationDefaults _resolveGenerationDefaults({
  required YamlMap rawYaml,
  required GrumpyGenerationDefaults defaults,
  required List<ProjectDiagnostic> diagnostics,
  required String configPath,
}) {
  final logger = grumpyLogger('config');
  final rawDefaults = rawYaml[_defaultsKey];
  if (rawDefaults == null) {
    return defaults;
  }
  if (rawDefaults is! YamlMap) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_defaults',
        severity: DiagnosticSeverity.warning,
        message: 'defaults must be a map in $configPath; using defaults.',
        path: configPath,
      ),
    );
    return defaults;
  }

  final common = Map<String, Object?>.from(defaults.common);
  final unitDefaults = defaults.unitDefaults.map(
    (unit, values) => MapEntry(unit, Map<String, Object?>.from(values)),
  );

  for (final entry in rawDefaults.entries) {
    final rawKey = entry.key;
    if (rawKey is! String) {
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_defaults_key',
          severity: DiagnosticSeverity.warning,
          message: 'Ignoring non-string defaults key in $configPath.',
          path: configPath,
        ),
      );
      continue;
    }

    final section = _parseDefaultSectionMap(
      entry.value,
      diagnostics: diagnostics,
      configPath: configPath,
      sectionName: rawKey,
    );
    if (section == null) {
      continue;
    }

    if (rawKey == _commonDefaultsKey) {
      common.addAll(section);
      continue;
    }

    if (!_supportedDefaultUnits.contains(rawKey)) {
      logger.warning('Ignoring unknown defaults section "$rawKey".');
      diagnostics.add(
        ProjectDiagnostic(
          code: 'unknown_config_defaults_section',
          severity: DiagnosticSeverity.warning,
          message: 'Ignoring unknown defaults section "$rawKey" in $configPath.',
          path: configPath,
        ),
      );
      continue;
    }

    unitDefaults[rawKey] = {
      ...?unitDefaults[rawKey],
      ...section,
    };
  }

  return GrumpyGenerationDefaults(common: common, unitDefaults: unitDefaults);
}

Map<String, Object?>? _parseDefaultSectionMap(
  Object? value, {
  required List<ProjectDiagnostic> diagnostics,
  required String configPath,
  required String sectionName,
}) {
  if (value is! YamlMap) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_defaults_section',
        severity: DiagnosticSeverity.warning,
        message:
            'defaults.$sectionName must be a map in $configPath; ignoring it.',
        path: configPath,
      ),
    );
    return null;
  }

  final resolved = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_defaults_value_key',
          severity: DiagnosticSeverity.warning,
          message:
              'Ignoring non-string defaults key in defaults.$sectionName from $configPath.',
          path: configPath,
        ),
      );
      continue;
    }
    final normalized = _normalizeDefaultValue(entry.value);
    if (normalized == null) {
      diagnostics.add(
        ProjectDiagnostic(
          code: 'invalid_config_defaults_value',
          severity: DiagnosticSeverity.warning,
          message:
              'Ignoring unsupported value for defaults.$sectionName.${entry.key} in $configPath.',
          path: configPath,
        ),
      );
      continue;
    }
    resolved[entry.key as String] = normalized;
  }

  return resolved;
}

Object? _normalizeDefaultValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is YamlList) {
    final normalized = <Object?>[];
    for (final item in value) {
      final resolved = _normalizeDefaultValue(item);
      if (resolved == null && item != null) {
        return null;
      }
      normalized.add(resolved);
    }
    return normalized;
  }
  if (value is YamlMap) {
    final normalized = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        return null;
      }
      final resolved = _normalizeDefaultValue(entry.value);
      if (resolved == null && entry.value != null) {
        return null;
      }
      normalized[entry.key as String] = resolved;
    }
    return normalized;
  }
  return null;
}

Future<File> _resolveConfigFile(String projectRoot) async {
  final yaml = File(p.join(projectRoot, 'grumpy.yaml'));
  if (await yaml.exists()) {
    return yaml;
  }
  return File(p.join(projectRoot, 'grumpy.yml'));
}

Map<ModuleCategory, List<String>> _copyCategoryPaths(
  Map<ModuleCategory, List<String>> source,
) {
  return source.map(
    (category, paths) => MapEntry(category, List<String>.from(paths)),
  );
}

List<String> _orderedUnique(List<String> values) {
  final unique = <String>[];
  for (final value in values) {
    if (!unique.contains(value)) {
      unique.add(value);
    }
  }
  return unique;
}
