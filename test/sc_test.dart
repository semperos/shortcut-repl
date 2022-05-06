import 'package:test/test.dart';

void main() {
  test('default', () {
    expect(2, 2);
  });
}

/**
 * ls
 * - list tasks in story
 * - list stories in epic
 * - list epics in milestone
 * - list stories in iteration
 *
 * pwd
 * - print current container
 *
 * whoami
 * - print Shortcut user info (or name of token, or...?)
 *
 * cd <type>/<id>
 * - change current container to be the thing identified by type + id
 *
 * ? or help
 * - no args, general help
 * - textual search otherwise
 *
 * (select :from story :where (== story.epic myepic))
 *
 * <symbol>
 * - if defined, print value
 * - if not defined, prompt for value and set
 */