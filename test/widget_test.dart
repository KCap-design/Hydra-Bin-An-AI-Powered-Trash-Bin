import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_bin/models/leaderboard_item.dart';

void main() {
  test('LeaderboardItem has correct fields', () {
    const item = LeaderboardItem(
      rank: 1, name: 'Test', points: 100,
      email: 'test@example.com', activeFrame: 'none',
    );
    expect(item.rank, 1);
    expect(item.name, 'Test');
    expect(item.points, 100);
  });
}
