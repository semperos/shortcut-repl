import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sc_cli/src/sc_config.dart';
import 'package:sc_cli/src/sc.dart';

abstract class ScApiContract {
  // # CRUD

  // ## Stories
  Future<ScStory> createStory(ScEnv env, Map<String, dynamic> storyData);
  Future<ScStory> getStory(ScEnv env, String storyPublicId);
  Future<ScStory> updateStory(
      ScEnv env, String storyPublicId, Map<String, dynamic> updateMap);
  // bool archiveStory(String storyPublicId);
  // bool deleteStory(String storyPublicId);

  // ## Tasks
  Future<ScTask> createTask(
      ScEnv env, String storyPublicId, Map<String, dynamic> taskData);
  Future<ScTask> getTask(ScEnv env, String storyPublicId, String taskPublicId);
  Future<ScTask> updateTask(ScEnv env, String storyPublicId,
      String taskPublicId, Map<String, dynamic> updateMap);
  // bool deleteTask(String storyPublicId, String taskPublicId);

  Future<ScComment> createComment(
      ScEnv env, String storyPublicId, Map<String, dynamic> commentData);
  Future<ScComment> getComment(
      ScEnv env, String storyPublicId, String commentPublicId);
  Future<ScComment> updateComment(ScEnv env, String storyPublicId,
      String commentPublicId, Map<String, dynamic> updateMap);

  Future<ScEpicComment> createEpicComment(
      ScEnv env, String epicPublicId, Map<String, dynamic> commentData);
  Future<ScEpicComment> createEpicCommentComment(ScEnv env, String epicPublicId,
      String epicCommentPublicId, Map<String, dynamic> commentData);
  Future<ScEpicComment> getEpicComment(
      ScEnv env, String epicPublicId, String commentPublicId);
  Future<ScEpicComment> updateEpicComment(ScEnv env, String epicPublicId,
      String commentPublicId, Map<String, dynamic> updateMap);

  // ## Epics
  Future<ScEpic> createEpic(ScEnv env, Map<String, dynamic> epicData);
  Future<ScEpic> getEpic(ScEnv env, String epicPublicId);
  Future<ScList> getEpics(ScEnv env);
  Future<ScEpic> updateEpic(
      ScEnv env, String epicPublicId, Map<String, dynamic> updateMap);
  // bool archiveEpic(String epicPublicId);
  // bool deleteEpic(String epicPublicId);

  // ## Members
  Future<ScMember> getCurrentMember(ScEnv env);
  Future<ScMember> getMember(ScEnv env, String memberPublicId);
  Future<ScList> getMembers(ScEnv env);

  // ## Teams, a.k.a. Groups
  Future<ScTeam> getTeam(ScEnv env, String teamPublicId);
  Future<ScTeam> updateTeam(
      ScEnv env, String teamPublicId, Map<String, dynamic> updateMap);
  Future<ScList> getTeams(ScEnv env);

  // ## Workflows
  Future<ScWorkflow> getWorkflow(ScEnv env, String workflowPublicId);
  Future<ScList> getWorkflows(ScEnv env);

  // ## Epic Workflows
  // NB: There is only one per workspace.
  Future<ScEpicWorkflow> getEpicWorkflow(ScEnv env);

  // ## Milestones
  Future<ScMilestone> createMilestone(
      ScEnv env, Map<String, dynamic> milestoneData);
  Future<ScMilestone> getMilestone(ScEnv env, String milestonePublicId);
  Future<ScList> getMilestones(ScEnv env);
  Future<ScMilestone> updateMilestone(
      ScEnv env, String milestonePublicId, Map<String, dynamic> updateMap);
  // NB: Milestones don't support archival
  // bool archiveMilestone(String milestonePublicId);
  // bool deleteMilestone(String milestonePublicId);

  // ## Iterations
  Future<ScIteration> createIteration(
      ScEnv env, Map<String, dynamic> iterationData);
  Future<ScIteration> getIteration(ScEnv env, String iterationPublicId);
  Future<ScList> getIterations(ScEnv env);
  Future<ScIteration> updateIteration(
      ScEnv env, String iterationPublicId, Map<String, dynamic> updateMap);
  // bool archiveIteration(String iterationPublicId);
  // bool deleteIteration(String iterationPublicId);

  // # Labels
  Future<ScLabel> createLabel(ScEnv env, Map<String, dynamic> labelData);
  Future<ScLabel> getLabel(ScEnv env, String labelPublicId);
  Future<ScList> getLabels(ScEnv env);
  Future<ScLabel> updateLabel(
      ScEnv env, String labelPublicId, Map<String, dynamic> updateMap);

  // # Listings
  Future<ScList> getEpicsInMilestone(ScEnv env, String milestonePublicId);
  Future<ScList> getStoriesInEpic(ScEnv env, String epicPublicId);
  Future<ScList> getStoriesInIteration(ScEnv env, String iterationPublicId);
  Future<ScList> getStoriesInTeam(ScEnv env, String teamPublicId);
  Future<ScList> getStoriesWithLabel(ScEnv env, String labelPublicId);
  // Future<List<ScComment>> getCommentsInStory(String storyPublicId);
  Future<ScList> getTasksInStory(ScEnv env, String storyPublicId);

  // Search
  Future<ScMap> search(ScEnv env, ScString queryString);
  Future<ScList> findStories(ScEnv env, Map<String, dynamic> findMap);
}

const arrayValuesKey = '__sc_array-values';

abstract class ScClient implements ScApiContract {
  /// HTTP client used for requests to Shortcut's API
  final HttpClient client = HttpClient();

  ScClient(this.host, this.apiToken);

  /// Shortcut API token used to communicate via its RESTful API.
  final String? apiToken;

  final String host;
}

class ScLiveClient extends ScClient {
  ScLiveClient(String host, String? apiToken) : super(host, apiToken);

  File? recordedCallsFile;
  bool shouldRecordCalls = false;

  @override
  Future<ScEpic> getEpic(ScEnv env, String epicPublicId) async {
    final taba = await authedCall(env, "/epics/$epicPublicId");
    return taba.epic(env);
  }

  @override
  Future<ScList> getEpics(ScEnv env) async {
    final taba = await authedCall(env, "/epics");
    return taba.epics(env);
  }

  @override
  Future<ScEpic> updateEpic(
      ScEnv env, String epicPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/epics/$epicPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.epic(env);
  }

  @override
  Future<ScIteration> getIteration(ScEnv env, String iterationPublicId) async {
    final taba = await authedCall(env, "/iterations/$iterationPublicId");
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> getMilestone(ScEnv env, String milestonePublicId) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId");
    return taba.milestone(env);
  }

  @override
  Future<ScStory> getStory(ScEnv env, String storyPublicId) async {
    final taba = await authedCall(env, "/stories/$storyPublicId");
    return taba.story(env);
  }

  @override
  Future<ScList> getEpicsInMilestone(
      ScEnv env, String milestonePublicId) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId/epics");
    return taba.epics(env);
  }

  @override
  Future<ScEpic> createEpic(ScEnv env, Map<String, dynamic> epicData) async {
    final taba = await authedCall(env, "/epics",
        httpVerb: HttpVerb.post, body: epicData);
    return taba.epic(env);
  }

  @override
  Future<ScIteration> createIteration(
      ScEnv env, Map<String, dynamic> iterationData) async {
    final taba = await authedCall(env, "/iterations",
        httpVerb: HttpVerb.post, body: iterationData);
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> createMilestone(
      ScEnv env, Map<String, dynamic> milestoneData) async {
    final taba = await authedCall(env, "/milestones",
        httpVerb: HttpVerb.post, body: milestoneData);
    return taba.milestone(env);
  }

  @override
  Future<ScStory> createStory(ScEnv env, Map<String, dynamic> storyData) async {
    final taba = await authedCall(env, "/stories",
        httpVerb: HttpVerb.post, body: storyData);
    return taba.story(env);
  }

  @override
  Future<ScLabel> createLabel(ScEnv env, Map<String, dynamic> labelData) async {
    final taba = await authedCall(env, "/labels",
        httpVerb: HttpVerb.post, body: labelData);
    return taba.label(env);
  }

  @override
  Future<ScList> getStoriesInEpic(ScEnv env, String epicPublicId) async {
    final taba = await authedCall(env, "/epics/$epicPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScList> getStoriesInIteration(
      ScEnv env, String iterationPublicId) async {
    final taba =
        await authedCall(env, "/iterations/$iterationPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScIteration> updateIteration(ScEnv env, String iterationPublicId,
      Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/iterations/$iterationPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.iteration(env);
  }

  @override
  Future<ScMilestone> updateMilestone(ScEnv env, String milestonePublicId,
      Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/milestones/$milestonePublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.milestone(env);
  }

  @override
  Future<ScStory> updateStory(
      ScEnv env, String storyPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/stories/$storyPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.story(env);
  }

  @override
  Future<ScMember> getCurrentMember(ScEnv env) async {
    final tabaShallow = await authedCall(env, '/member');
    final shallowMember = tabaShallow.currentMember(env);
    return await getMember(env, shallowMember.idString);
  }

  @override
  Future<ScMap> search(ScEnv env, ScString queryString) async {
    final taba = await authedCall(env, '/search',
        body: {'query': queryString.value}, httpVerb: HttpVerb.get);
    return taba.search(env);
  }

  @override
  Future<ScList> getTasksInStory(ScEnv env, String storyPublicId) async {
    final story = await getStory(env, storyPublicId);
    final tasksList = story.data[ScString('tasks')];
    if (tasksList == null || (tasksList as ScList).isEmpty) {
      return ScList([]);
    } else {
      return tasksList;
    }
  }

  @override
  Future<ScTask> createTask(
      ScEnv env, String storyPublicId, Map<String, dynamic> taskData) async {
    final taba = await authedCall(env, "/stories/$storyPublicId/tasks",
        httpVerb: HttpVerb.post, body: taskData);
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScTask> getTask(
      ScEnv env, String storyPublicId, String taskPublicId) async {
    final taba =
        await authedCall(env, "/stories/$storyPublicId/tasks/$taskPublicId");
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScTask> updateTask(ScEnv env, String storyPublicId,
      String taskPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(
        env, "/stories/$storyPublicId/tasks/$taskPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.task(env, storyPublicId);
  }

  @override
  Future<ScComment> createComment(
      ScEnv env, String storyPublicId, Map<String, dynamic> commentData) async {
    final taba = await authedCall(env, "/stories/$storyPublicId/comments",
        httpVerb: HttpVerb.post, body: commentData);
    return taba.comment(env, storyPublicId);
  }

  @override
  Future<ScComment> getComment(
      ScEnv env, String storyPublicId, String commentPublicId) async {
    final taba = await authedCall(
        env, "/stories/$storyPublicId/comments/$commentPublicId");
    return taba.comment(env, storyPublicId);
  }

  @override
  Future<ScComment> updateComment(ScEnv env, String storyPublicId,
      String commentPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(
        env, "/stories/$storyPublicId/comments/$commentPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.comment(env, storyPublicId);
  }

  @override
  Future<ScEpicComment> createEpicComment(
      ScEnv env, String epicPublicId, Map<String, dynamic> commentData) async {
    final taba = await authedCall(env, "/epics/$epicPublicId/comments",
        httpVerb: HttpVerb.post, body: commentData);
    return taba.epicComment(env, epicPublicId);
  }

  @override
  Future<ScEpicComment> createEpicCommentComment(ScEnv env, String epicPublicId,
      String epicCommentPublicId, Map<String, dynamic> commentData) async {
    final taba = await authedCall(
        env, "/epics/$epicPublicId/comments/$epicCommentPublicId",
        httpVerb: HttpVerb.post, body: commentData);
    return taba.epicComment(env, epicPublicId);
  }

  @override
  Future<ScEpicComment> getEpicComment(
      ScEnv env, String epicPublicId, String commentPublicId) async {
    final taba =
        await authedCall(env, "/epics/$epicPublicId/comments/$commentPublicId");
    return taba.epicComment(env, epicPublicId);
  }

  @override
  Future<ScEpicComment> updateEpicComment(ScEnv env, String epicPublicId,
      String commentPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(
        env, "/epics/$epicPublicId/comments/$commentPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.epicComment(env, epicPublicId);
  }

  @override
  Future<ScList> getWorkflows(ScEnv env) async {
    final taba = await authedCall(env, "/workflows");
    return taba.workflows(env);
  }

  @override
  Future<ScTeam> getTeam(ScEnv env, String teamPublicId) async {
    final taba = await authedCall(env, "/groups/$teamPublicId");
    return taba.team(env, teamPublicId);
  }

  @override
  Future<ScTeam> updateTeam(
      ScEnv env, String teamPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/groups/$teamPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.team(env, teamPublicId);
  }

  @override
  Future<ScList> getTeams(ScEnv env) async {
    final taba = await authedCall(env, "/groups");
    return taba.teams(env);
  }

  @override
  Future<ScWorkflow> getWorkflow(ScEnv env, String workflowPublicId) async {
    final taba = await authedCall(env, "/workflows/$workflowPublicId");
    return taba.workflow(env, workflowPublicId);
  }

  @override
  Future<ScEpicWorkflow> getEpicWorkflow(ScEnv env) async {
    final taba = await authedCall(env, "/epic-workflow");
    return taba.epicWorkflow(env);
  }

  @override
  Future<ScList> getMembers(ScEnv env) async {
    final taba = await authedCall(env, "/members");
    return taba.members(env);
  }

  @override
  Future<ScMember> getMember(ScEnv env, String memberPublicId) async {
    final taba = await authedCall(env, "/members/$memberPublicId");
    return taba.member(env);
  }

  @override
  Future<ScList> getStoriesInTeam(ScEnv env, String teamPublicId) async {
    final taba = await authedCall(env, "/groups/$teamPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScList> getIterations(ScEnv env) async {
    final taba = await authedCall(env, "/iterations");
    return taba.iterations(env);
  }

  @override
  Future<ScList> findStories(ScEnv env, Map<String, dynamic> findMap) async {
    final taba = await authedCall(env, "/stories/search",
        httpVerb: HttpVerb.post, body: findMap);
    return taba.stories(env);
  }

  @override
  Future<ScList> getMilestones(ScEnv env) async {
    final taba = await authedCall(env, "/milestones");
    return taba.milestones(env);
  }

  @override
  Future<ScLabel> getLabel(ScEnv env, String labelPublicId) async {
    final taba = await authedCall(env, "/labels/$labelPublicId");
    return taba.label(env);
  }

  @override
  Future<ScList> getLabels(ScEnv env) async {
    final taba = await authedCall(env, "/labels");
    return taba.labels(env);
  }

  @override
  Future<ScList> getStoriesWithLabel(ScEnv env, String labelPublicId) async {
    final taba = await authedCall(env, "/labels/$labelPublicId/stories");
    return taba.stories(env);
  }

  @override
  Future<ScLabel> updateLabel(
      ScEnv env, String labelPublicId, Map<String, dynamic> updateMap) async {
    final taba = await authedCall(env, "/labels/$labelPublicId",
        httpVerb: HttpVerb.put, body: updateMap);
    return taba.label(env);
  }

  Future<ThereAndBackAgain> authedCall(ScEnv env, String path,
      {HttpVerb httpVerb = HttpVerb.get, Map<String, dynamic>? body}) async {
    if (recordedCallsFile == null) {
      shouldRecordCalls = checkShouldRecordCalls();
      recordedCallsFile ??= File([
        getDefaultBaseConfigDirPath(),
        'recorded-calls.jsonl'
      ].join(Platform.pathSeparator));
    }
    final uri =
        Uri(scheme: scheme, host: getShortcutHost(), path: "$basePath$path");
    HttpClientRequest request =
        await client.openUrl(methodFromVerb(httpVerb), uri);
    request
      ..headers.set('Shortcut-Token', "$apiToken")
      ..headers.contentType = ContentType.json;

    if (httpVerb == HttpVerb.post || httpVerb == HttpVerb.put || body != null) {
      final bodyJson = jsonEncode(
        body,
        toEncodable: handleJsonNonEncodable,
      );
      request
        ..headers.contentLength = bodyJson.length
        ..write(bodyJson);
    }

    final requestDt = DateTime.now();
    HttpClientResponse response = await request.close();
    final responseDt = DateTime.now();

    Map<String, dynamic> bodyData = {};
    if (response.statusCode.toString().startsWith('2')) {
      final bodyString = await response.transform(utf8.decoder).join();
      final jsonData = jsonDecode(bodyString);
      if (jsonData is List) {
        bodyData[arrayValuesKey] = jsonData;
      } else if (jsonData is Map) {
        bodyData = jsonData as Map<String, dynamic>;
      } else {
        throw UnrecognizedResponseException(request, response);
      }
    } else {
      final responseContents = StringBuffer();

      await for (var data in response.transform(utf8.decoder)) {
        responseContents.write(data);
      }

      if (response.statusCode == 404) {
        throw EntityNotFoundException("Entity not found at $path");
      } else if (response.statusCode == 400) {
        throw BadRequestException(
            "HTTP 400 Bad Request: The request wasn't quite right. See details below.\n${responseContents.toString()}",
            request,
            response);
      } else if (response.statusCode == 401) {
        throw BadRequestException(
            "HTTP 401 Not Authorized: Make sure you have SHORTCUT_API_TOKEN defined in your environment correctly.",
            request,
            response);
      } else if (response.statusCode == 422) {
        throw BadRequestException(
            "HTTP 422 Unprocessable: The request wasn't quite right. See details below.\n${responseContents.toString()}",
            request,
            response);
      } else {
        stderr.writeln("HTTP Request: ${request.method} ${request.uri}");
        stderr.writeln(
            "HTTP Response: ${response.statusCode} Something went especially wrong. See details below.\n${responseContents.toString()}");
        throw BadResponseException(
            "HTTP Response: ${response.statusCode} Something went especially wrong. See details below.\n${responseContents.toString()}",
            request,
            response);
      }
    }

    final requestMap = request.toMap(requestDt);
    Map<String, dynamic> responseMap =
        response.toMap(requestDt, responseDt, bodyData);
    final taba = ThereAndBackAgain(requestMap, responseMap);
    if (shouldRecordCalls) {
      final json = jsonEncode(taba);
      await recordedCallsFile?.writeAsString("$json\n", mode: FileMode.append);
    }
    return taba;
  }
}

extension on HttpClientRequest {
  Map<String, dynamic> toMap(DateTime when) {
    return {'uri': uri.toString(), 'timestamp': when.toIso8601String()};
  }
}

extension on HttpClientResponse {
  /// To account for REST endpoints that return JSON arrays vs. objects, this
  /// [toMap] expects the caller to supply the parsed [bodyData].
  Map<String, dynamic> toMap(
      DateTime requestDt, DateTime responseDt, Map<String, dynamic> bodyData) {
    return {
      'body': bodyData,
      'duration': responseDt.difference(requestDt).inMilliseconds,
      'statusCode': statusCode,
      'timestamp': responseDt.toIso8601String(),
    };
  }
}

Object? handleJsonNonEncodable(Object? nonEncodable) {
  if (nonEncodable is DateTime) {
    return nonEncodable.toIso8601String();
  }
  return null;
}

String methodFromVerb(HttpVerb httpVerb) {
  switch (httpVerb) {
    case HttpVerb.get:
      return 'GET';
    case HttpVerb.put:
      return 'PUT';
    case HttpVerb.post:
      return 'POST';
    case HttpVerb.delete:
      return 'DELETE';
  }
}

class ThereAndBackAgain {
  ThereAndBackAgain(this.request, this.response);
  final Map<String, dynamic> request;
  final Map<String, dynamic> response;

  static ThereAndBackAgain fromJson(String tabaJson) {
    final jsonData = jsonDecode(tabaJson);
    final requestData = jsonData['request'];
    final responseData = jsonData['response'];
    return ThereAndBackAgain(requestData, responseData);
  }

  Map<String, dynamic> toJsonMap() {
    return {
      'request': request,
      'response': response,
      'timestamp': response['timestamp'],
      'duration': response['duration'],
      'version': recordedCallsVersion,
    };
  }

  List<dynamic> arrayBody() {
    return response['body'][arrayValuesKey];
  }

  Map<String, dynamic> objectBody() {
    return response['body'];
  }

  ScEpic epic(ScEnv env) {
    Map<String, dynamic> epic = objectBody();
    return ScEpic.fromMap(env, epic);
  }

  ScList epics(ScEnv env) {
    List<dynamic> epics = arrayBody();
    return ScList(epics.map((e) => ScEpic.fromMap(env, e)).toList());
  }

  ScStory story(ScEnv env) {
    Map<String, dynamic> story = objectBody();
    return ScStory.fromMap(env, story);
  }

  ScList stories(ScEnv env) {
    List<dynamic> stories = arrayBody();
    return ScList(stories.map((e) => ScStory.fromMap(env, e)).toList());
  }

  ScTask task(ScEnv env, String storyPublicId) {
    Map<String, dynamic> task = objectBody();
    return ScTask.fromMap(env, ScString(storyPublicId), task);
  }

  ScComment comment(ScEnv env, String storyPublicId) {
    Map<String, dynamic> comment = objectBody();
    return ScComment.fromMap(env, ScString(storyPublicId), comment);
  }

  ScEpicComment epicComment(ScEnv env, String epicPublicId) {
    Map<String, dynamic> epicComment = objectBody();
    return ScEpicComment.fromMap(env, ScString(epicPublicId), epicComment);
  }

  ScMilestone milestone(ScEnv env) {
    Map<String, dynamic> milestone = objectBody();
    return ScMilestone.fromMap(env, milestone);
  }

  ScList milestones(ScEnv env) {
    List<dynamic> milestones = arrayBody();
    return ScList(milestones.map((e) => ScMilestone.fromMap(env, e)).toList());
  }

  ScIteration iteration(ScEnv env) {
    Map<String, dynamic> iteration = objectBody();
    return ScIteration.fromMap(env, iteration);
  }

  ScList iterations(ScEnv env) {
    List<dynamic> iterations = arrayBody();
    return ScList(iterations.map((e) => ScIteration.fromMap(env, e)).toList());
  }

  ScMember currentMember(ScEnv env) {
    Map<String, dynamic> member = objectBody();
    return ScMember.fromMap(env, member);
  }

  ScWorkflow workflow(ScEnv env, String workflowPublicId) {
    Map<String, dynamic> workflow = objectBody();
    return ScWorkflow.fromMap(env, workflow);
  }

  ScEpicWorkflow epicWorkflow(ScEnv env) {
    Map<String, dynamic> epicWorkflow = objectBody();
    return ScEpicWorkflow.fromMap(env, epicWorkflow);
  }

  ScList workflows(ScEnv env) {
    List<dynamic> workflows = arrayBody();
    return ScList(workflows.map((e) => ScWorkflow.fromMap(env, e)).toList());
  }

  ScTeam team(ScEnv env, String teamPublicId) {
    Map<String, dynamic> team = objectBody();
    return ScTeam.fromMap(env, team);
  }

  ScList teams(ScEnv env) {
    List<dynamic> teams = arrayBody();
    return ScList(teams.map((e) => ScTeam.fromMap(env, e)).toList());
  }

  ScMember member(ScEnv env) {
    Map<String, dynamic> member = objectBody();
    return ScMember.fromMap(env, member);
  }

  ScList members(ScEnv env) {
    List<dynamic> members = arrayBody();
    return ScList(members.map((e) => ScMember.fromMap(env, e)).toList());
  }

  ScLabel label(ScEnv env) {
    Map<String, dynamic> label = objectBody();
    return ScLabel.fromMap(env, label);
  }

  ScList labels(ScEnv env) {
    List<dynamic> labels = arrayBody();
    return ScList(labels.map((e) => ScLabel.fromMap(env, e)).toList());
  }

  ScMap search(ScEnv env) {
    final searchResults = objectBody();
    final storyResults = searchResults['stories'] as Map<String, dynamic>;
    final epicResults = searchResults['epics'] as Map<String, dynamic>;
    final storiesData = storyResults['data'] as List;
    final epicsData = epicResults['data'] as List;
    final stories = storiesData.map((data) => ScStory.fromMap(env, data));
    final epics = epicsData.map((data) => ScEpic.fromMap(env, data));
    return ScMap({
      ScString('stories'): ScList(stories.toList()),
      ScString('epics'): ScList(epics.toList()),
    });
  }
}
