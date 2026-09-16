/// A kind of book a reader likes — asked once in onboarding, changeable in
/// settings' profile section, and used to fill the search tab's
/// recommendation rows.
enum ReadingTaste {
  fantasy('fantasy', 'fantasy'),
  scienceFiction('science fiction', 'science fiction'),
  mystery('mystery & thriller', 'thrillers'),
  romance('romance', 'romance'),
  historicalFiction('historical fiction', 'historical fiction'),
  literary('literary fiction', 'literary fiction'),
  horror('horror', 'horror'),
  youngAdult('young adult', 'young adult fiction'),
  classics('classics', 'classics'),
  memoir('biography & memoir', 'biography & autobiography'),
  selfHelp('self-help', 'self-help'),
  history('history', 'history'),
  science('science', 'science'),
  business('business', 'business & economics'),
  philosophy('philosophy', 'philosophy'),
  poetry('poetry', 'poetry'),
  graphicNovels('graphic novels', 'comics & graphic novels'),
  humor('humour', 'humor');

  const ReadingTaste(this.label, this.subject);

  /// What the reader sees.
  final String label;

  /// The Google Books `subject:` it searches.
  final String subject;
}
