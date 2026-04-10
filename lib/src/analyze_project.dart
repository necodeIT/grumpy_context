import 'config_loader.dart';
import 'logging.dart';
import 'models.dart';
import 'module_scanner.dart';
import 'pubspec_reader.dart';

/// Analyzes the Dart or Flutter project rooted at [projectRoot].
///
/// The returned [ProjectContext] contains the resolved discovery configuration,
/// dependency declarations, discovered modules, and any diagnostics produced
/// while reading `pubspec.yaml` or `grumpy.yaml` and scanning the source tree.
Future<ProjectContext> analyzeProject(String projectRoot) async {
  final logger = grumpyLogger('analyzer');
  final diagnostics = <ProjectDiagnostic>[];

  logger.info('Starting project analysis for $projectRoot.');

  final configResult = await loadGrumpyConfig(projectRoot);
  diagnostics.addAll(configResult.diagnostics);

  final pubspecResult = await readPubspec(projectRoot);
  diagnostics.addAll(pubspecResult.diagnostics);

  if (configResult.hasFatalError) {
    logger.warning(
      'Skipping module discovery because config resolution failed.',
    );
    return ProjectContext(
      name: pubspecResult.name,
      dependencies: pubspecResult.dependencies,
      modules: const <ProjectModule>[],
      units: const <ProjectUnit>[],
      diagnostics: diagnostics,
      config: configResult.config,
    );
  }

  final moduleScanResult = await scanModules(
    projectRoot: projectRoot,
    config: configResult.config,
  );
  diagnostics.addAll(moduleScanResult.diagnostics);

  logger.info(
    'Finished project analysis for $projectRoot with '
    '${moduleScanResult.modules.length} modules.',
  );

  return ProjectContext(
    name: pubspecResult.name,
    dependencies: pubspecResult.dependencies,
    modules: moduleScanResult.modules,
    units: moduleScanResult.modules.expand((module) => module.units).toList(),
    diagnostics: diagnostics,
    config: configResult.config,
  );
}
