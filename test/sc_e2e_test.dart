@Tags(['e2e'])

import 'dart:convert';
import 'dart:math';

import 'package:sc_cli/src/sc.dart';
import 'package:sc_cli/src/sc_api.dart' show ScLiveClient;
import 'package:sc_cli/src/sc_config.dart';
import 'package:test/test.dart';

const configParentStoryRaw = r'''
{"parent": {"entityType": "story", "entityId": "212751"}}
''';
const configParentEpicRaw = r'''
{"parent": {"entityType": "epic", "entityId": "90143"}}
''';
const configParentMilestoneRaw = r'''
{"parent": {"entityType": "milestone", "entityId": "209564"}}
''';
const configNoParentRaw = r'''
{}
''';
final configParentStory = jsonDecode(configParentStoryRaw);
final configParentEpic = jsonDecode(configParentEpicRaw);
final configParentMilestone = jsonDecode(configParentMilestoneRaw);
final configNoParent = jsonDecode(configNoParentRaw);

final client = ScLiveClient(getShortcutHost(), getShortcutApiToken());

void main() {
  group('Ctx with container', () {
    test('milestone', () {
      final env = ScEnv.fromMap(client, configParentMilestone);
      expect(env.parentEntity?.id, ScString('209564'));
      expect(env.parentEntity, TypeMatcher<ScMilestone>());
    });
    test('iteration', () {
      final json = jsonDecode('''
{"parent": {"entityType": "iteration", "entityId": "abcd"}}
''');
      final env = ScEnv.fromMap(client, json);
      expect(env.parentEntity?.id, ScString('abcd'));
      expect(env.parentEntity, TypeMatcher<ScIteration>());
    });
  });

  group('Commands', () {
    group('pwd', () {
      test('Epic parent', () {
        final env = ScEnv.fromMap(client, configParentEpic);
        final res = env.interpret('pwd');
        expect(res, TypeMatcher<ScEpic>());
      });
      test('Story parent', () {
        final env = ScEnv.fromMap(client, configParentStory);
        final res = env.interpret('pwd');
        expect(res, TypeMatcher<ScStory>());
      });
    });
    group('ls', () {
      test('No parent', () {
        final env = ScEnv.fromMap(client, configNoParent);
        final res = env.interpret('ls');
        expect(res, TypeMatcher<ScMember>());
        final member = res as ScMember;
        expect(member.id, ScString("aaaaaaaaa-1111-4444-aaaa-ffffffffffff"));
        expect(member.data[ScString('mention_name')], ScString('example'));
      });
      test('Epic parent', () {
        final env = ScEnv.fromMap(client, configParentEpic);
        final storyIdSet = <ScString>{
          ScString('90371'),
          ScString('90372'),
          ScString('77912'),
          ScString('90144'),
          ScString('90370')
        };
        final stories = env.interpret('ls') as ScList;
        expect(stories.length, 5);
        expect(stories.innerList.map((s) => (s as ScStory).id).toSet(),
            storyIdSet);
      });
      test('Milestone parent', () {
        final env = ScEnv.fromMap(client, configParentMilestone);
        final epicIdSet = <ScString>{ScString('209565'), ScString('207081')};
        final epics = env.interpret('ls') as ScList;
        expect(epics.innerList.map((e) => (e as ScEpic).id).toSet(), epicIdSet);
      });
    });

    group('story', () {
      test('story <id>', (() async {
        final env = ScEnv.fromMap(client, configParentMilestone);
        final story = await env.client.getStory(env, '284');
        expect(story.id, ScString('284'));
      }));
    });

    group('epic', () {
      test('epic fields...', () async {
        final env = ScEnv.fromMap(client, configParentMilestone);

        // Setup
        final epicOld = await env.client.getEpic(env, '55955');
        // When using live client:
        // await epicOld.update(env, {
        //   'planned_start_date': DateTime(2020),
        //   'completed_at_override': DateTime(2021)
        // });

        final newPlannedStartDate =
            DateTime.now().add(Duration(minutes: Random().nextInt(1439)));
        final newCompletedAtOverrideDate =
            newPlannedStartDate.add(Duration(days: 30));
        final epicNew = await epicOld.update(env, {
          'planned_start_date': newPlannedStartDate,
          'completed_at_override': newCompletedAtOverrideDate
        });
        expect(epicOld.data[ScString('planned_start_date')],
            TypeMatcher<ScString>());
        expect(epicNew.data[ScString('planned_start_date')],
            TypeMatcher<ScString>());
        expect(epicOld.data[ScString('planned_start_date')],
            isNot(epicNew.data[ScString('planned_start_date')]));

        expect(epicOld.data[ScString('completed_at_override')],
            TypeMatcher<ScString>());
        expect(epicNew.data[ScString('completed_at_override')],
            TypeMatcher<ScString>());
        expect(epicOld.data[ScString('completed_at_override')],
            isNot(epicNew.data[ScString('completed_at_override')]));
      });
    });
    group('Search', () {
      test('Default', () {
        final env = ScEnv.fromMap(client, configNoParent);
        final searchResults = env.interpret('select | search');
        expect(searchResults, TypeMatcher<ScMap>());
      });
    });
    group('Fetching', () {
      test('fetch-all', () {
        final env = ScEnv.fromMap(client, configNoParent);
        env.interpret('fetch-all');
      });
    });
  });
}
