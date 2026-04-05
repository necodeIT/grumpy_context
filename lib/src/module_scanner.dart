import 'dart:io';

import 'package:path/path.dart' as p;

import 'logging.dart';
import 'models.dart';

final class ModuleScanResult {
  const ModuleScanResult({required this.modules, required this.diagnostics});

  final List<ProjectModule> modules;
  final List<ProjectDiagnostic> diagnostics;
}

Future<ModuleScanResult> scanModules({
  required String projectRoot,
  required ResolvedGrumpyConfig config,
}) async {
  final logger = grumpyLogger('scanner');
  final diagnostics = <ProjectDiagnostic>[];
  final modulesByName = <String, _MutableModule>{};

  for (final moduleRoot in config.moduleRoots) {
    final rootDirectory = Directory(p.join(projectRoot, moduleRoot));
    logger.info('Scanning module root ${rootDirectory.path}.');
    if (!await rootDirectory.exists()) {
      continue;
    }

    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }

      final module = await _scanModuleDirectory(
        projectRoot: projectRoot,
        moduleRoot: moduleRoot,
        moduleDirectory: entity,
        config: config,
      );
      if (module == null) {
        continue;
      }

      logger.info('Discovered module "${module.name}" in ${module.rootPath}.');
      final existing = modulesByName[module.name];
      if (existing == null) {
        modulesByName[module.name] = module;
      } else {
        logger.warning(
          'Module "${module.name}" was found in multiple roots; merging inventories.',
        );
        diagnostics.add(
          ProjectDiagnostic(
            code: 'duplicate_module_root',
            severity: DiagnosticSeverity.warning,
            message:
                'Module "${module.name}" was found in multiple roots and has been merged.',
            path: module.rootPath,
          ),
        );
        existing.merge(module);
      }
    }
  }

  final modules =
      modulesByName.values
          .map((module) => module.build(diagnostics: diagnostics))
          .toList()
        ..sort((left, right) => left.name.compareTo(right.name));

  if (modules.isEmpty) {
    logger.warning('No modules matching the configured rules were found.');
    diagnostics.add(
      const ProjectDiagnostic(
        code: 'no_modules_found',
        severity: DiagnosticSeverity.warning,
        message:
            'No modules matching the configured discovery rules were found.',
      ),
    );
  }

  return ModuleScanResult(modules: modules, diagnostics: diagnostics);
}

Future<_MutableModule?> _scanModuleDirectory({
  required String projectRoot,
  required String moduleRoot,
  required Directory moduleDirectory,
  required ResolvedGrumpyConfig config,
}) async {
  final buckets = <ModuleCategory, _MutableBucket>{};
  var hasAnyCategory = false;

  for (final category in ModuleCategory.values) {
    final aliases = config.categoryPaths[category] ?? const <String>[];
    final foundAliases = <_FoundAliasBucket>[];

    for (final alias in aliases) {
      final categoryDirectory = Directory(p.join(moduleDirectory.path, alias));
      if (!await categoryDirectory.exists()) {
        continue;
      }

      foundAliases.add(
        _FoundAliasBucket(
          relativeDirectoryPath: p.relative(
            categoryDirectory.path,
            from: projectRoot,
          ),
          files: await _collectDartFiles(
            projectRoot: projectRoot,
            directory: categoryDirectory,
          ),
        ),
      );
    }

    if (foundAliases.isNotEmpty) {
      hasAnyCategory = true;
    }

    buckets[category] = _MutableBucket.fromAliases(foundAliases);
  }

  if (!hasAnyCategory) {
    return null;
  }

  return _MutableModule(
    name: p.basename(moduleDirectory.path),
    rootPath: p.relative(moduleDirectory.path, from: projectRoot),
    categories: buckets,
    sourceRoots: <String>{moduleRoot},
  );
}

Future<List<String>> _collectDartFiles({
  required String projectRoot,
  required Directory directory,
}) async {
  final files = <String>[];
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && p.extension(entity.path) == '.dart') {
      files.add(p.relative(entity.path, from: projectRoot));
    }
  }
  files.sort();
  return files;
}

final class _MutableModule {
  _MutableModule({
    required this.name,
    required this.rootPath,
    required this.categories,
    required this.sourceRoots,
  });

  final String name;
  final String rootPath;
  final Map<ModuleCategory, _MutableBucket> categories;
  final Set<String> sourceRoots;

  void merge(_MutableModule other) {
    sourceRoots.addAll(other.sourceRoots);
    for (final category in ModuleCategory.values) {
      categories[category]!.merge(other.categories[category]!);
    }
  }

  ProjectModule build({required List<ProjectDiagnostic> diagnostics}) {
    final logger = grumpyLogger('diagnostics');
    final missingCategories = <String>[];
    final builtCategories = <ModuleCategory, ModuleBucket>{};

    for (final category in ModuleCategory.values) {
      final bucket = categories[category]!;
      if (!bucket.exists) {
        missingCategories.add(category.name);
      }
      if (bucket.aliasDirectories.length > 1) {
        logger.warning(
          'Module "$name" has multiple directories for ${category.name}; merging them.',
        );
        diagnostics.add(
          ProjectDiagnostic(
            code: 'merged_category_aliases',
            severity: DiagnosticSeverity.warning,
            message:
                'Module "$name" has multiple directories for ${category.name}; their file inventories were merged.',
            path: bucket.directoryPath,
          ),
        );
      }
      builtCategories[category] = ModuleBucket(
        directoryPath: bucket.directoryPath,
        files: bucket.sortedFiles,
      );
    }

    if (missingCategories.isNotEmpty) {
      final diagnostic = ProjectDiagnostic(
        code: 'partial_module',
        severity: DiagnosticSeverity.warning,
        message:
            'Module "$name" is missing categories: ${missingCategories.join(', ')}.',
        path: rootPath,
      );
      logger.warning(diagnostic.message);
      diagnostics.add(diagnostic);
    }

    return ProjectModule(
      name: name,
      rootPath: rootPath,
      categories: builtCategories,
    );
  }
}

final class _MutableBucket {
  _MutableBucket({
    required this.directoryPath,
    required this.aliasDirectories,
    required Set<String> files,
  }) : _files = files;

  factory _MutableBucket.fromAliases(List<_FoundAliasBucket> aliases) {
    return _MutableBucket(
      directoryPath: aliases.isEmpty
          ? null
          : aliases.first.relativeDirectoryPath,
      aliasDirectories: aliases
          .map((alias) => alias.relativeDirectoryPath)
          .toSet(),
      files: aliases.expand((alias) => alias.files).toSet(),
    );
  }

  String? directoryPath;
  final Set<String> aliasDirectories;
  final Set<String> _files;

  bool get exists => directoryPath != null;

  List<String> get sortedFiles {
    final files = _files.toList();
    files.sort();
    return files;
  }

  void merge(_MutableBucket other) {
    directoryPath ??= other.directoryPath;
    aliasDirectories.addAll(other.aliasDirectories);
    _files.addAll(other._files);
  }
}

final class _FoundAliasBucket {
  const _FoundAliasBucket({
    required this.relativeDirectoryPath,
    required this.files,
  });

  final String relativeDirectoryPath;
  final List<String> files;
}
