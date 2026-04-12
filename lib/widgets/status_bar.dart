import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Top status bar overlay showing location, connection, and provider info.
class StatusBar extends StatelessWidget {
  final String locationName;
  final bool isOnline;
  final bool isAnalyzing;
  final String providerName;
  final bool isFrozen;

  const StatusBar({
    super.key,
    required this.locationName,
    required this.isOnline,
    required this.isAnalyzing,
    required this.providerName,
    required this.isFrozen,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.glassBorder, width: 1),
              ),
              child: Row(
                children: [
                  // Location icon + name
                  Icon(
                    Icons.location_on_rounded,
                    color: AppTheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      locationName,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Frozen indicator
                  if (isFrozen) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pause_rounded,
                              color: AppTheme.warning, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'FROZEN',
                            style: TextStyle(
                              color: AppTheme.warning,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  // Online/offline indicator
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isOnline ? AppTheme.accent : AppTheme.error,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isOnline ? AppTheme.accent : AppTheme.error)
                              .withOpacity(0.5),
                          blurRadius: 6,
                        ),
                      ],
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
