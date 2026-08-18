/// Accumulates onboarding answers across pages so they can be written
/// to Supabase in one call once the account exists — `readingGoal` and
/// `readingMinutesPerDay` from Q1/Q2, `name`/`description` from the
/// new-reader path. Each page that collects an answer copies it into
/// the draft and passes the updated value forward, the same way
/// `session` is threaded through the whole flow.
class OnboardingProfileDraft {
  const OnboardingProfileDraft({
    this.readingGoal,
    this.readingMinutesPerDay,
    this.name,
    this.description,
  });

  final int? readingGoal;
  final int? readingMinutesPerDay;
  final String? name;
  final String? description;

  OnboardingProfileDraft copyWith({
    int? readingGoal,
    int? readingMinutesPerDay,
    String? name,
    String? description,
  }) {
    return OnboardingProfileDraft(
      readingGoal: readingGoal ?? this.readingGoal,
      readingMinutesPerDay: readingMinutesPerDay ?? this.readingMinutesPerDay,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }
}
