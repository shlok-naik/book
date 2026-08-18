import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/dotted_background.dart';
import '../../../../core/widgets/tilted_marquee_wall.dart';
import '../../domain/paywall_pricing.dart';
import '../widgets/soft_pill_button.dart';
import 'one_more_thing_page.dart';

/// First finish-category screen: sprung right after an account exists
/// (new sign-up or a returning sign-in). No real billing is wired up
/// yet — the close button and the CTA both just move on to
/// [OneMoreThingPage] — but the screen is real, and [pricing] is
/// already validated the way it will need to be once a store SDK is
/// feeding it.
///
/// ## Layout
///
/// Top-to-bottom: header, headline, three rows of feature pills,
/// side-by-side pricing cards, a free-trial toggle, then the CTA. The
/// column is split into three groups laid out `spaceBetween` inside the
/// bounded card, so leftover vertical room is distributed *between*
/// sections instead of pooling at the bottom — that, plus the
/// [_Metrics] scale factor, is what keeps the proportions steady from
/// a small phone to a tablet without anything overflowing.
///
/// ## Component reuse
///
/// Nothing here is a one-off:
/// * feature pills scroll via [TiltedMarqueeWall], the same widget (and
///   the same tilt, speeds and alternating directions) the tutorial
///   step's command wall uses;
/// * the toggle and CTA are both built on [SoftPillShell] /
///   [SoftPillButton], the pill treatment every other onboarding button
///   already wears;
/// * colors come from [AppColors] and spacing/radii from
///   [AppSpacing] / [AppRadius], so the screen follows the reader's
///   light/dark choice like the rest of the flow.
class PaywallPage extends StatefulWidget {
  const PaywallPage({super.key, this.pricing = PaywallPricing.placeholder});

  /// Prices to display. Validated before use — see [PaywallPricing]; an
  /// invalid set renders [_PricingUnavailable] instead of the cards.
  final PaywallPricing pricing;

  @override
  State<PaywallPage> createState() => _PaywallPageState();
}

enum _Plan { monthly, yearly }

/// Everything that scales with viewport height, resolved once per
/// build so the sections can't drift apart from each other.
///
/// [scale] is keyed to a ~760pt reference viewport and clamped, so a
/// short screen tightens uniformly rather than letting one section
/// collapse while its neighbour keeps full size.
class _Metrics {
  _Metrics(double height) : scale = (height / 760).clamp(0.82, 1.0);

  final double scale;

  double get gapSm => AppSpacing.sm * scale;
  double get gapMd => AppSpacing.md * scale;
  double get gapLg => AppSpacing.lg * scale;

  /// Height of a single marquee row. The pill's own padding is fixed,
  /// so this only needs to leave room for one line of label.
  double get featureRowHeight => 40 * scale;

  /// Both pricing cards are pinned to this height, so selecting one
  /// changes only its *width* — the row never reflows vertically.
  double get pricingCardHeight => 104 * scale;

  /// Vertical room reserved above the pricing row for the savings tag,
  /// which is deliberately positioned outside the card's top edge.
  double get badgeOverhang => 12 * scale;
}

class _PaywallPageState extends State<PaywallPage> {
  /// Yearly leads on load — it's the better value, and the savings tag
  /// only has something to say while it's the selected plan.
  _Plan _plan = _Plan.yearly;

  /// Free trials are a yearly-plan perk, so this and [_plan] are kept
  /// consistent in both directions: see [_selectPlan] / [_setTrial].
  bool _trialEnabled = false;

  /// Feature pills, three rows to match the reference's structure and
  /// [CommandWall]'s. Each pill sizes itself to its label, so rows end
  /// up pleasantly ragged rather than a rigid grid.
  static const _featureRows = <List<(IconData, String)>>[
    [
      (Icons.memory, 'long term memory'),
      (Icons.auto_awesome, 'access to cactus ai'),
      (Icons.menu_book_outlined, 'book recommendations'),
    ],
    [
      (Icons.tune, 'preference tracking'),
      (Icons.chat_bubble_outline, 'use natural language'),
      (Icons.favorite_border, 'support the creator'),
    ],
    [
      (Icons.insights_outlined, 'reading stats'),
      (Icons.local_fire_department_outlined, 'streak tracking'),
      (Icons.all_inclusive, 'unlimited books'),
    ],
  ];

  void _continue() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OneMoreThingPage()));
  }

  void _selectPlan(_Plan plan) {
    setState(() {
      _plan = plan;
      // Monthly can't carry a trial, so picking it silently drops one
      // rather than leaving the toggle claiming something untrue.
      if (plan == _Plan.monthly) _trialEnabled = false;
    });
  }

  void _setTrial(bool enabled) {
    setState(() {
      _trialEnabled = enabled;
      // ...and the reverse: opting into a trial moves the reader onto
      // the only plan that offers one.
      if (enabled) _plan = _Plan.yearly;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pricing = widget.pricing;
    final priceable = pricing.isValid;

    return Scaffold(
      backgroundColor: colors.background,
      body: DottedBackground(
        child: SafeArea(
          bottom: false,
          // A near-full-bleed card: only a sliver of a gap up top, so
          // the dotted background still reads behind the rounded
          // corners without this becoming a half-sheet.
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: ColoredBox(
                color: colors.surface,
                child: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final m = _Metrics(constraints.maxHeight);

                      return Column(
                        children: [
                          _Header(onClose: _continue, metrics: m),
                          // Leftover height is split 2:3 between the two
                          // gaps rather than evenly, which pulls the
                          // feature wall up under the headline and lets
                          // the breathing room fall where the reference
                          // puts it — above the commit block.
                          const Spacer(flex: 2),
                          _FeatureWall(rows: _featureRows, metrics: m),
                          const Spacer(flex: 3),
                          _CommitBlock(
                            metrics: m,
                            pricing: pricing,
                            priceable: priceable,
                            plan: _plan,
                            trialEnabled: _trialEnabled,
                            onSelectPlan: _selectPlan,
                            onTrialChanged: _setTrial,
                            onSubmit: priceable ? _continue : null,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wordmark + PRO badge + close, then the headline quote beneath.
class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.metrics});

  final VoidCallback onClose;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            metrics.gapMd,
            AppSpacing.sm,
            0,
          ),
          child: Row(
            // Centered so the badge sits level with the middle of the
            // wordmark rather than riding its baseline.
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'cactus',
                style: GoogleFonts.ebGaramond(
                  fontSize: 32 * metrics.scale,
                  fontWeight: FontWeight.w600,
                  color: colors.primaryText,
                ),
              ),
              SizedBox(width: metrics.gapSm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryText,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'PRO',
                  style: GoogleFonts.inter(
                    fontSize: 13 * metrics.scale,
                    fontWeight: FontWeight.w800,
                    color: colors.background,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // IconButton keeps the 48x48 minimum tap target even
              // though the glyph is small.
              IconButton(
                onPressed: onClose,
                tooltip: 'close',
                icon: Icon(Icons.close, color: colors.secondaryText),
              ),
            ],
          ),
        ),
        SizedBox(height: metrics.gapLg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Text(
            '"the limits of my language mean the limits of my world."',
            textAlign: TextAlign.center,
            style: GoogleFonts.ebGaramond(
              fontSize: 18 * metrics.scale,
              fontStyle: FontStyle.italic,
              height: 1.4,
              color: colors.primaryText,
            ),
          ),
        ),
        SizedBox(height: metrics.gapSm),
        Text(
          '- ludwig wittgenstein',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13 * metrics.scale,
            color: colors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// The three auto-scrolling rows of feature pills.
///
/// The visual is [TiltedMarqueeWall] — shared with the tutorial step —
/// but semantically it's one static list: the marquee repeats each pill
/// several times to fake an endless loop, which a screen reader would
/// otherwise read out four times over. So the whole wall is excluded
/// from the tree and replaced with a single summarising label.
class _FeatureWall extends StatelessWidget {
  const _FeatureWall({required this.rows, required this.metrics});

  final List<List<(IconData, String)>> rows;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final labels = [
      for (final row in rows)
        for (final (_, label) in row) label,
    ];

    return Semantics(
      label: 'included with cactus PRO: ${labels.join(', ')}',
      container: true,
      child: ExcludeSemantics(
        child: TiltedMarqueeWall(
          rowHeight: metrics.featureRowHeight,
          rowSpacing: metrics.gapSm,
          rows: [
            for (final row in rows)
              [
                for (final (icon, label) in row)
                  _FeaturePill(icon: icon, label: label, metrics: metrics),
              ],
          ],
        ),
      ),
    );
  }
}

/// A single feature pill — sized to its own label rather than to a
/// fixed width, so "book recommendations" is visibly longer than
/// "reading stats". Same self-sizing idea as the tutorial's command
/// chips.
class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.metrics,
  });

  final IconData icon;
  final String label;
  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        // min, and no Expanded around the label — that's what lets the
        // pill hug its text.
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.accent, size: 18 * metrics.scale),
          SizedBox(width: metrics.gapSm),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14 * metrics.scale,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: colors.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pricing cards, trial toggle and CTA — the part of the screen that
/// asks for a decision, pinned together at the bottom.
class _CommitBlock extends StatelessWidget {
  const _CommitBlock({
    required this.metrics,
    required this.pricing,
    required this.priceable,
    required this.plan,
    required this.trialEnabled,
    required this.onSelectPlan,
    required this.onTrialChanged,
    required this.onSubmit,
  });

  final _Metrics metrics;
  final PaywallPricing pricing;
  final bool priceable;
  final _Plan plan;
  final bool trialEnabled;
  final ValueChanged<_Plan> onSelectPlan;
  final ValueChanged<bool> onTrialChanged;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        metrics.gapLg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (priceable)
            _PricingRow(
              metrics: metrics,
              pricing: pricing,
              plan: plan,
              onSelectPlan: onSelectPlan,
            )
          else
            const _PricingUnavailable(),
          SizedBox(height: metrics.gapMd),
          _TrialToggle(
            value: trialEnabled,
            // A trial can't be offered without a price to fall back to
            // when it ends.
            onChanged: priceable ? onTrialChanged : null,
            metrics: metrics,
          ),
          SizedBox(height: metrics.gapSm),
          SoftPillButton(
            label: trialEnabled ? 'start free trial' : 'join now',
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}

/// The two plans, touching, filling the row exactly.
///
/// Widths are computed from the row's own width rather than left to
/// `Expanded`, for two reasons: the split has to *animate* when
/// selection moves (flex factors snap), and the two widths must always
/// sum to exactly the available width so the cards stay flush with no
/// seam or overflow.
class _PricingRow extends StatelessWidget {
  const _PricingRow({
    required this.metrics,
    required this.pricing,
    required this.plan,
    required this.onSelectPlan,
  });

  final _Metrics metrics;
  final PaywallPricing pricing;
  final _Plan plan;
  final ValueChanged<_Plan> onSelectPlan;

  /// Share of the row the selected card claims. The other card takes
  /// the remainder, so the pair always spans the full width.
  static const _selectedShare = 0.56;

  @override
  Widget build(BuildContext context) {
    final savings = pricing.savingsPercent;

    return Padding(
      // Reserves room for the savings tag, which sits above the card's
      // top edge and would otherwise be clipped by whatever is above.
      padding: EdgeInsets.only(top: metrics.badgeOverhang),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final total = constraints.maxWidth;
          final selectedWidth = total * _selectedShare;
          final unselectedWidth = total - selectedWidth;
          final monthlySelected = plan == _Plan.monthly;

          return Row(
            children: [
              _PricingCard(
                label: 'monthly',
                priceLine: '\$${pricing.monthlyPerMonth.toStringAsFixed(2)}/mo',
                selected: monthlySelected,
                width: monthlySelected ? selectedWidth : unselectedWidth,
                height: metrics.pricingCardHeight,
                // Square where it meets its neighbour, rounded on the
                // outside — the two read as one connected control.
                radius: const BorderRadius.horizontal(
                  left: Radius.circular(AppRadius.md),
                ),
                onTap: () => onSelectPlan(_Plan.monthly),
                metrics: metrics,
              ),
              _PricingCard(
                label: 'yearly',
                priceLine: '\$${pricing.yearlyPerMonth.toStringAsFixed(2)}/mo',
                subLine: '\$${pricing.yearlyPerYear.toStringAsFixed(0)}/yr',
                // Hidden unless the saving is both real and this card is
                // the one being emphasised.
                badge: savings == null ? null : 'save $savings%',
                selected: !monthlySelected,
                width: monthlySelected ? unselectedWidth : selectedWidth,
                height: metrics.pricingCardHeight,
                radius: const BorderRadius.horizontal(
                  right: Radius.circular(AppRadius.md),
                ),
                onTap: () => onSelectPlan(_Plan.yearly),
                metrics: metrics,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.label,
    required this.priceLine,
    required this.selected,
    required this.width,
    required this.height,
    required this.radius,
    required this.onTap,
    required this.metrics,
    this.subLine,
    this.badge,
  });

  final String label;
  final String priceLine;
  final String? subLine;
  final String? badge;
  final bool selected;
  final double width;
  final double height;
  final BorderRadius radius;
  final VoidCallback onTap;
  final _Metrics metrics;

  static const _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Selected keeps full-strength text; unselected drops back so the
    // emphasis reads at a glance. Alphas stay above the 4.5:1 contrast
    // floor against `background` in both themes.
    final labelColor = selected
        ? colors.secondaryText
        : colors.secondaryText.withValues(alpha: 0.55);
    final priceColor = selected
        ? colors.primaryText
        : colors.primaryText.withValues(alpha: 0.45);
    final subColor = colors.secondaryText.withValues(
      alpha: selected ? 0.8 : 0.45,
    );

    final semanticPrice = subLine == null
        ? priceLine
        : '$priceLine, billed $subLine';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label plan, $semanticPrice${badge != null && selected ? ', $badge' : ''}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            // The savings tag deliberately overhangs the top edge.
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOut,
                width: width,
                height: height,
                padding: EdgeInsets.symmetric(
                  horizontal: metrics.gapMd,
                  vertical: metrics.gapSm,
                ),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? colors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: _duration,
                      style: GoogleFonts.inter(
                        fontSize: 13 * metrics.scale,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                      child: Text(label),
                    ),
                    SizedBox(height: metrics.gapSm),
                    // scaleDown keeps the price legible-but-unclipped
                    // mid-animation, while the card is still narrowing.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AnimatedDefaultTextStyle(
                        duration: _duration,
                        style: GoogleFonts.inter(
                          fontSize: (selected ? 22 : 16) * metrics.scale,
                          fontWeight: FontWeight.w700,
                          color: priceColor,
                        ),
                        child: Text(priceLine),
                      ),
                    ),
                    if (subLine != null) ...[
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: AnimatedDefaultTextStyle(
                          duration: _duration,
                          style: GoogleFonts.inter(
                            fontSize: 12 * metrics.scale,
                            color: subColor,
                          ),
                          child: Text(subLine!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (badge != null && selected)
                Positioned(
                  top: -metrics.badgeOverhang,
                  right: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      badge!,
                      style: GoogleFonts.inter(
                        fontSize: 11 * metrics.scale,
                        fontWeight: FontWeight.w700,
                        color: colors.background,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "activate free trial" + switch, wearing [SoftPillShell] so it matches
/// the CTA directly beneath it rather than introducing a second button
/// language.
class _TrialToggle extends StatelessWidget {
  const _TrialToggle({
    required this.value,
    required this.onChanged,
    required this.metrics,
  });

  final bool value;

  /// Null disables the control — used when there's no valid price to
  /// roll onto once a trial ends.
  final ValueChanged<bool>? onChanged;

  final _Metrics metrics;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onChanged != null;
    final tint = enabled ? colors.accent : colors.secondaryText;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: 'activate free trial',
      onTap: enabled ? () => onChanged!(!value) : null,
      child: ExcludeSemantics(
        child: SoftPillShell(
          tint: tint,
          child: InkWell(
            onTap: enabled ? () => onChanged!(!value) : null,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.gapMd,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'activate free trial',
                      style: GoogleFonts.inter(
                        fontSize: 16 * metrics.scale,
                        fontWeight: FontWeight.w600,
                        color: tint,
                      ),
                    ),
                  ),
                  Switch(
                    value: value,
                    onChanged: onChanged,
                    // WidgetStateProperty rather than the deprecated
                    // activeColor/inactiveThumbColor pair.
                    thumbColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? colors.background
                          : colors.secondaryText,
                    ),
                    trackColor: WidgetStateProperty.resolveWith(
                      // Off reads against the tinted pill behind it, so
                      // the track has to be the *background* tone —
                      // `divider` is too close to the tint to register.
                      (states) => states.contains(WidgetState.selected)
                          ? tint
                          : colors.background,
                    ),
                    trackOutlineColor: WidgetStateProperty.all(
                      Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the pricing cards when [PaywallPricing.isValid] is
/// false — a missing or malformed price is surfaced plainly rather than
/// rendered as `$NaN/mo`, and the CTA above is disabled alongside it.
class _PricingUnavailable extends StatelessWidget {
  const _PricingUnavailable();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 20, color: colors.secondaryText),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                "we couldn't load pricing right now. check your connection "
                'and try again in a moment.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.4,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
