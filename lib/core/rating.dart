import 'dart:math';

const minRating = 1;
const maxRating = 3;

bool isValidRating(int rating) => rating >= minRating && rating <= maxRating;

/// Business-facing tier letter for a stored rating int (1..3).
/// 3 = 'A' (strongest), 2 = 'B', 1 = 'C' (weakest).
const _tierLabels = {1: 'C', 2: 'B', 3: 'A'};

String ratingTierLabel(int rating) {
  assert(isValidRating(rating), 'rating $rating is outside $minRating..$maxRating');
  return _tierLabels[rating]!;
}

/// Rounds a numeric average (e.g. a team's average rating) to the nearest
/// valid rating and returns its tier letter.
String averageTierLabel(double average) =>
    ratingTierLabel(average.round().clamp(minRating, maxRating));
