/// A pickable set of typefaces for the whole app, from settings'
/// customisation page (the "fonts" tab, beside icons and themes).
///
/// The app sets type in three roles, and a font theme names one Google
/// Fonts family for each:
///
/// * [interfaceFamily] — page titles ("library", "stats"), section headings,
///   labels, pills and the command line. The app's own voice.
/// * [bodyFamily] — running text: author names, descriptions, settings rows.
/// * [bookTitleFamily] — the one thing every reader came for: book titles on
///   tiles, covers, the currently-reading card and the book page.
///
/// Onboarding, the paywall and the "cactus" wordmark keep their fixed
/// faces — they are designed pieces, not the reader's own shelf.
enum AppFontTheme {
  /// The app as it has always looked, and every install's default.
  original(
    label: 'original',
    interfaceFamily: 'JetBrains Mono',
    bodyFamily: 'Inter',
    bookTitleFamily: 'Fraunces',
  ),

  /// Set like a modern paperback: Literata — the face Google designed for
  /// reading e-books — for the page, with Garamond on the titles.
  book(
    label: 'book',
    interfaceFamily: 'Literata',
    bodyFamily: 'Literata',
    bookTitleFamily: 'EB Garamond',
  ),

  /// The two faces of the book trade's golden age: Caslon for the chrome,
  /// Baskerville for the words.
  classic(
    label: 'classic',
    interfaceFamily: 'Libre Caslon Text',
    bodyFamily: 'Libre Baskerville',
    bookTitleFamily: 'Libre Baskerville',
  ),

  /// A manuscript before it was typeset.
  typewriter(
    label: 'typewriter',
    interfaceFamily: 'Courier Prime',
    bodyFamily: 'Courier Prime',
    bookTitleFamily: 'Special Elite',
  ),

  /// A terminal readout.
  robotic(
    label: 'robotic',
    interfaceFamily: 'Share Tech Mono',
    bodyFamily: 'IBM Plex Mono',
    bookTitleFamily: 'Orbitron',
  );

  const AppFontTheme({
    required this.label,
    required this.interfaceFamily,
    required this.bodyFamily,
    required this.bookTitleFamily,
  });

  final String label;

  /// Google Fonts family names, exactly as `GoogleFonts.getFont` expects.
  final String interfaceFamily;
  final String bodyFamily;
  final String bookTitleFamily;
}
