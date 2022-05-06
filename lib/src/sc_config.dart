import 'dart:io';

const host = 'api.app.shortcut.com';
const basePath = '/api/v3';
const scheme = 'https';
const envFilePath = 'env.json';
const cacheMembersFilePath = 'cache_members.json';
const cacheTeamsFilePath = 'cache_teams.json';
const cacheWorkflowsFilePath = 'cache_workflows.json';
const cacheEpicWorkflowFilePath = 'cache_epic_workflow.json';
const historyFilePath = 'history.log';

String getShortcutHost() {
  return Platform.environment['SHORTCUT_API_HOST'] ?? host;
}

String? getShortcutApiToken() {
  return Platform.environment['SHORTCUT_API_TOKEN'];
}

const recordedCallsVersion = '1';

bool checkShouldRecordCalls() {
  return Platform.environment['SHORTCUT_RECORD_CALLS'] != null;
}

File getEnvFile() {
  final baseDirPath = getBaseConfigDirPath();
  final envFile = File([baseDirPath, envFilePath].join(Platform.pathSeparator));
  if (!envFile.existsSync()) {
    envFile.parent.createSync(recursive: true);
    envFile.writeAsStringSync('{}');
  }
  return envFile;
}

File getHistoryFile() {
  final baseDirPath = getBaseConfigDirPath();
  final historyFile =
      File([baseDirPath, historyFilePath].join(Platform.pathSeparator));
  if (!historyFile.existsSync()) {
    historyFile.parent.createSync(recursive: true);
    historyFile.writeAsStringSync('');
  }
  return historyFile;
}

File getCacheMembersFile() {
  final baseDirPath = getBaseConfigDirPath();
  final cacheMembersFile =
      File([baseDirPath, cacheMembersFilePath].join(Platform.pathSeparator));
  if (!cacheMembersFile.existsSync()) {
    cacheMembersFile.parent.createSync(recursive: true);
    cacheMembersFile.writeAsStringSync('{}');
  }
  return cacheMembersFile;
}

File getCacheTeamsFile() {
  final baseDirPath = getBaseConfigDirPath();
  final cacheTeamsFile =
      File([baseDirPath, cacheTeamsFilePath].join(Platform.pathSeparator));
  if (!cacheTeamsFile.existsSync()) {
    cacheTeamsFile.parent.createSync(recursive: true);
    cacheTeamsFile.writeAsStringSync('{}');
  }
  return cacheTeamsFile;
}

File getCacheWorkflowsFile() {
  final baseDirPath = getBaseConfigDirPath();
  final cacheWorkflowsFile =
      File([baseDirPath, cacheWorkflowsFilePath].join(Platform.pathSeparator));
  if (!cacheWorkflowsFile.existsSync()) {
    cacheWorkflowsFile.parent.createSync(recursive: true);
    cacheWorkflowsFile.writeAsStringSync('{}');
  }
  return cacheWorkflowsFile;
}

File getCacheEpicWorkflowFile() {
  final baseDirPath = getBaseConfigDirPath();
  final cacheWorkflowsFile = File(
      [baseDirPath, cacheEpicWorkflowFilePath].join(Platform.pathSeparator));
  if (!cacheWorkflowsFile.existsSync()) {
    cacheWorkflowsFile.parent.createSync(recursive: true);
    cacheWorkflowsFile.writeAsStringSync('{}');
  }
  return cacheWorkflowsFile;
}

/// Base configuration path on the user's computer. Uses synchronous methods
/// because constructors cannot use async and this is called from the [ScEnv]
/// constructor. Creates the directory if it doesn't exist; callers may need
/// to create individual files that they manage.
String getBaseConfigDirPath() {
  var baseDir = Platform.environment['HOME'];
  baseDir ??= '.';
  final configDirPath = Platform.environment['SHORTCUT_CONFIG_DIR'] ??
      [baseDir, '.config', 'shortcut-cli'].join(Platform.pathSeparator);
  final configDir = Directory(configDirPath);
  if (!configDir.existsSync()) {
    configDir.create(recursive: true);
  }
  return configDirPath;
}
