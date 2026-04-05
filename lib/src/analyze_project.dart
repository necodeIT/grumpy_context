import 'config_loader.dart';
import 'logging.dart';
import 'models.dart';
import 'module_scanner.dart';
import 'pubspec_reader.dart';

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
    diagnostics: diagnostics,
    config: configResult.config,
  );
}
