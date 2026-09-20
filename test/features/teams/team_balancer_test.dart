import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:volley_teams/core/failure.dart';
import 'package:volley_teams/features/sessions/domain/entities/team.dart';
import 'package:volley_teams/features/teams/domain/services/team_balancer.dart';

List<RatedPlayer> roster(List<int> ratings) => [
      for (var i = 0; i < ratings.length; i++)
        RatedPlayer(id: 'p$i', rating: ratings[i]),
    ];

double spreadOf(List<Team> teams) {
  final averages = teams.map((t) => t.averageRating);
  return averages.reduce(max) - averages.reduce(min);
}

/// Tie-robust check of "one player per tier on every team".
///
/// Tier j is `sorted[j*T .. j*T+T-1]` (ratings, highest first). If every team
/// has exactly one player per tier, then the j-th best rating of any team must
/// lie between the lowest and highest rating of tier j.
void expectOnePerTier(List<Team> teams, List<RatedPlayer> players) {
  final t = teams.length;
  final ratingOf = {for (final p in players) p.id: p.rating};
  final sorted = ratingOf.values.toList()..sort((a, b) => b.compareTo(a));
  for (final team in teams) {
    final ratings = [for (final id in team.playerIds) ratingOf[id]!]
      ..sort((a, b) => b.compareTo(a));
    for (var j = 0; j < ratings.length; j++) {
      final high = sorted[j * t];
      final low = sorted[min(j * t + t - 1, sorted.length - 1)];
      expect(
        ratings[j],
        inInclusiveRange(low, high),
        reason: 'team ${team.index} rank $j: $ratings vs tier [$low..$high]',
      );
    }
  }
}

void main() {
  const balancer = TeamBalancer();

  group('team count', () {
    test('rounds to the nearest whole team, minimum two', () {
      expect(TeamBalancer.teamCountFor(12, 6), 2);
      expect(TeamBalancer.teamCountFor(13, 6), 2);
      expect(TeamBalancer.teamCountFor(15, 6), 3); // 2.5 rounds up
      expect(TeamBalancer.teamCountFor(17, 6), 3);
      expect(TeamBalancer.teamCountFor(4, 6), 2); // never fewer than two
    });

    test('fewer than four players is rejected', () {
      final result = balancer.balance(
        players: roster([5, 4, 3]),
        teamSize: 6,
        random: Random(1),
      );
      expect(result.failure, isA<NotEnoughPlayers>());
    });

    test('team sizes: 13 -> 7+6, 17 -> 6+6+5, 15 -> 5+5+5', () {
      List<int> sizes(int n) {
        final teams = balancer
            .balance(
              players: roster(List.filled(n, 3)),
              teamSize: 6,
              random: Random(7),
            )
            .value;
        return teams.map((t) => t.playerIds.length).toList()..sort((a, b) => b.compareTo(a));
      }

      expect(sizes(13), [7, 6]);
      expect(sizes(17), [6, 6, 5]);
      expect(sizes(15), [5, 5, 5]);
    });
  });

  group('balancing', () {
    test('two teams of four each get one player of every rating', () {
      final teams = balancer
          .balance(
            players: roster([5, 5, 4, 4, 3, 3, 2, 2]),
            teamSize: 4,
            random: Random(3),
          )
          .value;
      for (final team in teams) {
        final ratings = team.playerIds
            .map((id) => [5, 5, 4, 4, 3, 3, 2, 2][int.parse(id.substring(1))])
            .toList()
          ..sort((a, b) => b.compareTo(a));
        expect(ratings, [5, 4, 3, 2]);
        expect(team.ratingTotal, 14);
      }
    });

    test('the three best players of a 3-team game are on different teams', () {
      final players = roster([5, 5, 5, 3, 3, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1]);
      for (var seed = 0; seed < 20; seed++) {
        final teams = balancer.balance(players: players, teamSize: 6, random: Random(seed)).value;
        expect(teams, hasLength(3));
        for (final team in teams) {
          final aces = team.playerIds.where((id) => players.firstWhere((p) => p.id == id).rating == 5);
          expect(aces, hasLength(1), reason: 'seed $seed team ${team.index}');
        }
      }
    });

    test('the same seed gives the same teams', () {
      final players = roster([5, 4, 4, 3, 3, 3, 2, 2, 1, 5, 4, 2, 3]);
      final a = balancer.balance(players: players, teamSize: 6, random: Random(99)).value;
      final b = balancer.balance(players: players, teamSize: 6, random: Random(99)).value;
      expect(a, b);
    });

    test('different seeds vary the teams', () {
      final players = roster(List.generate(12, (i) => 1 + i % 5));
      final draws = {
        for (var seed = 0; seed < 10; seed++)
          balancer
              .balance(players: players, teamSize: 6, random: Random(seed))
              .value
              .map((t) => t.playerIds.toSet())
              .toString(),
      };
      expect(draws.length, greaterThan(1));
    });
  });

  group('swap pass', () {
    test('narrows the spread of a raw draw that was unbalanced', () {
      // Found by scanning seeds: for seed 11 the raw draw has a spread of 1.0
      // and the swap pass brings it to 0.0.
      final players = roster([5, 4, 4, 3, 3, 2, 2, 1]);
      const seed = 11;

      final raw = const TeamBalancer(swapPass: false)
          .balance(players: players, teamSize: 4, random: Random(seed))
          .value;
      final balanced = balancer.balance(players: players, teamSize: 4, random: Random(seed)).value;

      expect(spreadOf(raw), greaterThan(0));
      expect(spreadOf(balanced), lessThan(spreadOf(raw)));
      expectOnePerTier(balanced, players);
    });
  });

  group('properties over random rosters', () {
    test('hold for 400 rosters', () {
      final meta = Random(2026);
      for (var run = 0; run < 400; run++) {
        final n = 4 + meta.nextInt(37); // 4..40 players
        final teamSize = 2 + meta.nextInt(7); // 2..8
        final players = roster([for (var i = 0; i < n; i++) 1 + meta.nextInt(5)]);
        final seed = meta.nextInt(1 << 30);
        final label = 'run $run n=$n teamSize=$teamSize seed=$seed';

        final teams = balancer.balance(players: players, teamSize: teamSize, random: Random(seed)).value;

        // Everyone assigned exactly once.
        final assigned = teams.expand((t) => t.playerIds).toList()..sort();
        expect(assigned, ([for (final p in players) p.id]..sort()), reason: label);

        // Team count and sizes.
        expect(teams, hasLength(TeamBalancer.teamCountFor(n, teamSize)), reason: label);
        final sizes = teams.map((t) => t.playerIds.length);
        expect(sizes.reduce(max) - sizes.reduce(min), lessThanOrEqualTo(1), reason: label);

        // Totals are consistent.
        final ratingOf = {for (final p in players) p.id: p.rating};
        for (final team in teams) {
          expect(team.ratingTotal, team.playerIds.fold<int>(0, (s, id) => s + ratingOf[id]!), reason: label);
        }

        // One player per tier on every team.
        expectOnePerTier(teams, players);

        // The swap pass never makes the spread worse.
        final raw = const TeamBalancer(swapPass: false)
            .balance(players: players, teamSize: teamSize, random: Random(seed))
            .value;
        expect(spreadOf(teams), lessThanOrEqualTo(spreadOf(raw) + 1e-9), reason: label);
      }
    });
  });
}
