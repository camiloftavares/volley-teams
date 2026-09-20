import 'dart:math';

import 'package:equatable/equatable.dart';

import '../../../../core/failure.dart';
import '../../../../core/result.dart';
import '../../../sessions/domain/entities/team.dart';

class RatedPlayer extends Equatable {
  const RatedPlayer({required this.id, required this.rating});

  final String id;
  final int rating;

  @override
  List<Object?> get props => [id, rating];
}

/// Splits players into balanced teams.
///
/// Players are ranked and cut into tiers of one player per team. Each tier is
/// dealt to the teams in random order, so no team gets two players from the
/// same tier (the strongest players never share a team). A swap pass then
/// narrows the gap between team average ratings, swapping only players of the
/// same tier so that guarantee is preserved.
class TeamBalancer {
  const TeamBalancer({this.swapPass = true});

  static const minPlayers = 4;
  static const _maxSwapIterations = 200;
  static const _epsilon = 1e-9;

  /// Disable only in tests, to compare against the raw draw.
  final bool swapPass;

  static int teamCountFor(int playerCount, int teamSize) =>
      max(2, (playerCount / teamSize).round());

  Result<List<Team>> balance({
    required List<RatedPlayer> players,
    required int teamSize,
    required Random random,
  }) {
    assert(teamSize >= 1);
    if (players.length < minPlayers) {
      return Err(NotEnoughPlayers(have: players.length, need: minPlayers));
    }
    final teamCount = teamCountFor(players.length, teamSize);
    final slots = _deal(_rank(players, random), teamCount, random);
    if (swapPass) _improve(slots);
    return Ok([
      for (var i = 0; i < teamCount; i++)
        Team(
          index: i,
          playerIds: [for (final slot in slots[i]) slot.player.id],
          ratingTotal: slots[i].fold(0, (sum, slot) => sum + slot.player.rating),
        ),
    ]);
  }

  /// Highest rating first; players with equal ratings are in random order.
  List<RatedPlayer> _rank(List<RatedPlayer> players, Random random) {
    final keyed = [
      for (final player in players) (player: player, tieBreak: random.nextDouble()),
    ]..sort((a, b) {
        final byRating = b.player.rating.compareTo(a.player.rating);
        return byRating != 0 ? byRating : a.tieBreak.compareTo(b.tieBreak);
      });
    return [for (final entry in keyed) entry.player];
  }

  List<List<_Slot>> _deal(List<RatedPlayer> ranked, int teamCount, Random random) {
    final teams = List.generate(teamCount, (_) => <_Slot>[]);
    for (var start = 0, tier = 0; start < ranked.length; start += teamCount, tier++) {
      final members = ranked.sublist(start, min(start + teamCount, ranked.length));
      // A shuffled team order gives each tier member a random distinct team;
      // a partial last tier therefore lands on random teams.
      final order = List<int>.generate(teamCount, (i) => i)..shuffle(random);
      for (var k = 0; k < members.length; k++) {
        teams[order[k]].add(_Slot(members[k], tier));
      }
    }
    return teams;
  }

  void _improve(List<List<_Slot>> teams) {
    final totals = [
      for (final team in teams) team.fold<int>(0, (sum, slot) => sum + slot.player.rating),
    ];
    final sizes = [for (final team in teams) team.length];

    for (var iteration = 0; iteration < _maxSwapIterations; iteration++) {
      var bestSpread = _spread(totals, sizes) - _epsilon;
      _Swap? best;
      for (var a = 0; a < teams.length; a++) {
        for (var b = a + 1; b < teams.length; b++) {
          for (var i = 0; i < teams[a].length; i++) {
            for (var j = 0; j < teams[b].length; j++) {
              final x = teams[a][i];
              final y = teams[b][j];
              if (x.tier != y.tier || x.player.rating == y.player.rating) continue;
              final delta = y.player.rating - x.player.rating;
              totals[a] += delta;
              totals[b] -= delta;
              final spread = _spread(totals, sizes);
              totals[a] -= delta;
              totals[b] += delta;
              if (spread < bestSpread) {
                bestSpread = spread;
                best = _Swap(a, i, b, j);
              }
            }
          }
        }
      }
      if (best == null) return;
      final x = teams[best.a][best.i];
      final y = teams[best.b][best.j];
      teams[best.a][best.i] = y;
      teams[best.b][best.j] = x;
      final delta = y.player.rating - x.player.rating;
      totals[best.a] += delta;
      totals[best.b] -= delta;
    }
  }

  double _spread(List<int> totals, List<int> sizes) {
    var lowest = double.infinity;
    var highest = double.negativeInfinity;
    for (var i = 0; i < totals.length; i++) {
      final average = totals[i] / sizes[i];
      lowest = min(lowest, average);
      highest = max(highest, average);
    }
    return highest - lowest;
  }
}

final class _Slot {
  const _Slot(this.player, this.tier);

  final RatedPlayer player;
  final int tier;
}

final class _Swap {
  const _Swap(this.a, this.i, this.b, this.j);

  final int a;
  final int i;
  final int b;
  final int j;
}
