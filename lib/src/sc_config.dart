import 'dart:io';

const apiHost = 'api.app.shortcut.com';
const appHost = 'app.shortcut.com';
const scheme = 'https';
const envFilePath = 'env.json';
const cacheMembersFilePath = 'cache_members.json';
const cacheTeamsFilePath = 'cache_teams.json';
const cacheLabelsFilePath = 'cache_labels.json';
const cacheWorkflowsFilePath = 'cache_workflows.json';
const cacheCustomFieldsFilePath = 'cache_custom_fields.json';
const cacheEpicWorkflowFilePath = 'cache_epic_workflow.json';
const historyFilePath = 'history.log';

String getShortcutApiHost() {
  return Platform.environment['SHORTCUT_API_HOST'] ?? apiHost;
}

String getShortcutAppHost() {
  return Platform.environment['SHORTCUT_APP_HOST'] ?? appHost;
}

String? getShortcutApiToken() {
  return Platform.environment['SHORTCUT_API_TOKEN'];
}

String? getShortcutAppCookie() {
  return Platform.environment['SHORTCUT_APP_COOKIE'];
}

String? getShortcutOrganization2() {
  return Platform.environment['SHORTCUT_ORGANIZATION2'];
}

String? getShortcutWorkspace2() {
  return Platform.environment['SHORTCUT_WORKSPACE2'];
}

const recordedCallsVersion = '1';

bool checkShouldRecordCalls() {
  return Platform.environment['SHORTCUT_RECORD_CALLS'] != null;
}

File getEnvFile(String baseConfigDirPath) {
  final envFile =
      File([baseConfigDirPath, envFilePath].join(Platform.pathSeparator));
  if (!envFile.existsSync()) {
    envFile.parent.createSync(recursive: true);
    envFile.writeAsStringSync('{}');
  }
  return envFile;
}

File getHistoryFile(String baseConfigDirPath) {
  final historyFile =
      File([baseConfigDirPath, historyFilePath].join(Platform.pathSeparator));
  if (!historyFile.existsSync()) {
    historyFile.parent.createSync(recursive: true);
    historyFile.writeAsStringSync('');
  }
  return historyFile;
}

File getCacheMembersFile(String baseConfigDirPath) {
  final cacheMembersFile = File(
      [baseConfigDirPath, cacheMembersFilePath].join(Platform.pathSeparator));
  if (!cacheMembersFile.existsSync()) {
    cacheMembersFile.parent.createSync(recursive: true);
    cacheMembersFile.writeAsStringSync('{}');
  }
  return cacheMembersFile;
}

File getCacheTeamsFile(String baseConfigDirPath) {
  final cacheTeamsFile = File(
      [baseConfigDirPath, cacheTeamsFilePath].join(Platform.pathSeparator));
  if (!cacheTeamsFile.existsSync()) {
    cacheTeamsFile.parent.createSync(recursive: true);
    cacheTeamsFile.writeAsStringSync('{}');
  }
  return cacheTeamsFile;
}

File getCacheLabelsFile(String baseConfigDirPath) {
  final cacheLabelsFile = File(
      [baseConfigDirPath, cacheLabelsFilePath].join(Platform.pathSeparator));
  if (!cacheLabelsFile.existsSync()) {
    cacheLabelsFile.parent.createSync(recursive: true);
    cacheLabelsFile.writeAsStringSync('{}');
  }
  return cacheLabelsFile;
}

File getCacheWorkflowsFile(String baseConfigDirPath) {
  final cacheWorkflowsFile = File(
      [baseConfigDirPath, cacheWorkflowsFilePath].join(Platform.pathSeparator));
  if (!cacheWorkflowsFile.existsSync()) {
    cacheWorkflowsFile.parent.createSync(recursive: true);
    cacheWorkflowsFile.writeAsStringSync('{}');
  }
  return cacheWorkflowsFile;
}

File getCacheCustomFieldsFile(String baseConfigDirPath) {
  final cacheWorkflowsFile = File([baseConfigDirPath, cacheCustomFieldsFilePath]
      .join(Platform.pathSeparator));
  if (!cacheWorkflowsFile.existsSync()) {
    cacheWorkflowsFile.parent.createSync(recursive: true);
    cacheWorkflowsFile.writeAsStringSync('{}');
  }
  return cacheWorkflowsFile;
}

File getCacheEpicWorkflowFile(String baseConfigDirPath) {
  final cacheWorkflowsFile = File([baseConfigDirPath, cacheEpicWorkflowFilePath]
      .join(Platform.pathSeparator));
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
String getDefaultBaseConfigDirPath() {
  var baseDir = Platform.environment['HOME'];
  baseDir ??= '.';
  final configDirPath = Platform.environment['SHORTCUT_CONFIG_DIR'] ??
      [baseDir, '.config', 'shortcut-repl'].join(Platform.pathSeparator);
  final configDir = Directory(configDirPath);
  if (!configDir.existsSync()) {
    configDir.create(recursive: true);
  }
  return configDirPath;
}
