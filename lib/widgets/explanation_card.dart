import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/explanation.dart';
import '../../theme/app_theme.dart';

/// Glassmorphic explanation card showing one explanation at a time.
class ExplanationCard extends StatefulWidget {
  final Explanation explanation;
  final int currentIndex;
  final int totalCount;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool isAnalyzing;

  const ExplanationCard({
    super.key,
    required this.explanation,
    required this.currentIndex,
    required this.totalCount,
    required this.onNext,
    required this.onPrevious,
    this.isAnalyzing = false,
  });

  @override
  State<ExplanationCard> createState() => _ExplanationCardState();
}

class _ExplanationCardState extends State<ExplanationCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _animController.forward();
  }

  @override
  void didUpdateWidget(ExplanationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _isExpanded = false;
      _animController.reset();
      _animController.forward();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.explanation;

    return FadeTransition(
      opacity: _fadeAnim,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.glassBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Navigation bar with arrows
                _buildNavBar(),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category + Headline
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exp.categoryIcon,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                exp.headline,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Summary
                        Text(
                          exp.summary.startsWith('{') || exp.summary.startsWith('[')
                              ? "Analyzing scene details..."
                              : exp.summary,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),

                        // Expandable details
                        if (exp.details.isNotEmpty &&
                            exp.details != exp.summary) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() => _isExpanded = !_isExpanded);
                            },
                            child: Row(
                              children: [
                                Text(
                                  _isExpanded ? 'Show less' : 'More details',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Icon(
                                  _isExpanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  color: AppTheme.primary,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                          if (_isExpanded) ...[
                            const SizedBox(height: 8),
                            Text(
                              exp.details,
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ],

                        // Source badges
                        if (exp.sources.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: exp.sources.map(_buildSourceBadge).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.glassBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Previous button
          _buildNavButton(
            Icons.chevron_left_rounded,
            widget.onPrevious,
            enabled: widget.totalCount > 1,
          ),
          const Spacer(),
          // Counter
          if (widget.isAnalyzing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            )
          else
            Text(
              '${widget.currentIndex + 1} of ${widget.totalCount}',
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          const Spacer(),
          // Next button
          _buildNavButton(
            Icons.chevron_right_rounded,
            widget.onNext,
            enabled: widget.totalCount > 1,
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback onTap,
      {bool enabled = true}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled ? AppTheme.glassWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String source) {
    final (icon, label) = switch (source.toLowerCase()) {
      'camera' || 'image' => ('📷', 'Camera'),
      'location' || 'gps' => ('📍', 'Location'),
      'news' => ('📰', 'News'),
      'time' => ('🕐', 'Time'),
      'heading' || 'compass' => ('🧭', 'Compass'),
      _ => ('🔗', source),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
