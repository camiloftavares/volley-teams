import 'package:equatable/equatable.dart';

class Team extends Equatable {
  const Team({
    required this.index,
    required this.playerIds,
    required this.ratingTotal,
  });

  final int index;
  final List<String> playerIds;
  final int ratingTotal;

  double get averageRating =>
      playerIds.isEmpty ? 0 : ratingTotal / playerIds.length;

  @override
  List<Object?> get props => [index, playerIds, ratingTotal];
}
