/// The average reading goal and reading time across every reader who
/// has answered Q1/Q2 — shown back on those same pages. Either field is
/// null until at least one reader has answered that question.
class OnboardingAverages {
  const OnboardingAverages({this.readingGoal, this.readingMinutesPerDay});

  final int? readingGoal;
  final int? readingMinutesPerDay;
}
