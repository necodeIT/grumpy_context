import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'logging.dart';
import 'models.dart';

final class ConfigLoadResult {
  const ConfigLoadResult({
    required this.config,
    required this.diagnostics,
    required this.hasFatalError,
  });

  final ResolvedGrumpyConfig config;
  final List<ProjectDiagnostic> diagnostics;
  final bool hasFatalError;
}

const _moduleRootsKey = 'module_roots';
const _layersKey = 'layers';

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

Future<ConfigLoadResult> loadGrumpyConfig(String projectRoot) async {
  final logger = grumpyLogger('config');
  final diagnostics = <ProjectDiagnostic>[];
  final defaults = ResolvedGrumpyConfig.defaults();
  final configFile = File(p.join(projectRoot, 'grumpy.yaml'));

  if (!await configFile.exists()) {
    logger.info('No grumpy.yaml found at ${configFile.path}; using defaults.');
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
    logger.severe('Failed to parse grumpy.yaml.', error, stackTrace);
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_yaml',
        severity: DiagnosticSeverity.error,
        message: 'Failed to parse grumpy.yaml: ${error.message}',
        path: 'grumpy.yaml',
      ),
    );
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: true,
    );
  }

  if (rawYaml == null) {
    logger.warning('grumpy.yaml is empty; using defaults.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'empty_config',
        severity: DiagnosticSeverity.warning,
        message: 'grumpy.yaml is empty; using default discovery rules.',
        path: 'grumpy.yaml',
      ),
    );
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: false,
    );
  }

  if (rawYaml is! YamlMap) {
    logger.severe('grumpy.yaml root must be a map.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'invalid_config_root',
        severity: DiagnosticSeverity.error,
        message: 'grumpy.yaml must contain a top-level map.',
        path: 'grumpy.yaml',
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
  );
  final layersResult = _resolveLayers(
    rawYaml: rawYaml,
    defaults: defaults.categoryPaths,
    diagnostics: diagnostics,
  );

  if (layersResult.hasFatalError) {
    logger.severe('grumpy.yaml contains fatal layer configuration errors.');
    return ConfigLoadResult(
      config: defaults,
      diagnostics: diagnostics,
      hasFatalError: true,
    );
  }

  final resolved = ResolvedGrumpyConfig(
    moduleRoots: moduleRoots,
    categoryPaths: layersResult.categoryPaths,
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
}) {
  final logger = grumpyLogger('config');
  final rawRoots = rawYaml[_moduleRootsKey];
  if (rawRoots == null) {
    return defaults;
  }

  if (rawRoots is! YamlList) {
    logger.warning('module_roots is not a list; using defaults.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'invalid_config_module_roots',
        severity: DiagnosticSeverity.warning,
        message:
            'module_roots must be a list of non-empty strings; using defaults.',
        path: 'grumpy.yaml',
      ),
    );
    return defaults;
  }

  final roots = <String>[];
  for (final item in rawRoots) {
    if (item is! String || item.trim().isEmpty) {
      logger.warning('module_roots contains an invalid entry; using defaults.');
      diagnostics.add(
        const ProjectDiagnostic(
          code: 'invalid_config_module_roots',
          severity: DiagnosticSeverity.warning,
          message:
              'module_roots must only contain non-empty strings; using defaults.',
          path: 'grumpy.yaml',
        ),
      );
      return defaults;
    }
    roots.add(p.normalize(item));
  }

  if (roots.isEmpty) {
    logger.warning('module_roots is empty; using defaults.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'invalid_config_module_roots',
        severity: DiagnosticSeverity.warning,
        message: 'module_roots must not be empty; using defaults.',
        path: 'grumpy.yaml',
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
      const ProjectDiagnostic(
        code: 'invalid_config_layers',
        severity: DiagnosticSeverity.error,
        message: 'layers must be a map in grumpy.yaml.',
        path: 'grumpy.yaml',
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
      );
      continue;
    }

    logger.warning('Ignoring unknown layer "$layerKey".');
    diagnostics.add(
      ProjectDiagnostic(
        code: 'unknown_config_layer',
        severity: DiagnosticSeverity.warning,
        message: 'Ignoring unknown layer "$layerKey" in grumpy.yaml.',
        path: 'grumpy.yaml',
      ),
    );
  }

  return _LayerResolutionResult(categoryPaths: resolved, hasFatalError: false);
}

void _resolveUtilsLayer({
  required Object? value,
  required List<ProjectDiagnostic> diagnostics,
  required Map<ModuleCategory, List<String>> resolved,
}) {
  final paths =
      _parsePathList(value) ??
      (value is YamlMap ? _parsePathList(value['paths']) : null);
  if (paths == null || paths.isEmpty) {
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'invalid_config_layer_paths',
        severity: DiagnosticSeverity.warning,
        message:
            'Layer "utils" must be a list of non-empty strings; using defaults.',
        path: 'grumpy.yaml',
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
}) {
  final logger = grumpyLogger('config');
  if (value is! YamlMap) {
    diagnostics.add(
      ProjectDiagnostic(
        code: 'invalid_config_layer',
        severity: DiagnosticSeverity.warning,
        message:
            'Layer "$layerKey" must be a map of path lists; using defaults for this layer.',
        path: 'grumpy.yaml',
      ),
    );
    return;
  }

  for (final entry in value.entries) {
    final subKey = entry.key;
    if (subKey is! String) {
      diagnostics.add(
        const ProjectDiagnostic(
          code: 'invalid_config_layer_key',
          severity: DiagnosticSeverity.warning,
          message: 'Ignoring non-string nested layer key in grumpy.yaml.',
          path: 'grumpy.yaml',
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
              'Ignoring unknown nested layer "$compoundKey" in grumpy.yaml.',
          path: 'grumpy.yaml',
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
          path: 'grumpy.yaml',
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
