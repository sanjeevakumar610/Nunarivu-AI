import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Coloured circle showing the first character of a name.
/// Colour is picked deterministically from [seed] so the same profile
/// always looks identical.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final int seed;
  final double size;
  final bool selected;

  const ProfileAvatar({
    super.key,
    required this.name,
    required this.seed,
    this.size = 56,
    this.selected = false,
  });

  // 8-colour palette tuned for both light + dark backgrounds.
  static const _palette = <Color>[
    Color(0xFF2E7D32), // emerald
    Color(0xFFEF6C00), // amber
    Color(0xFFC62828), // crimson
    Color(0xFF1565C0), // azure
    Color(0xFF6A1B9A), // amethyst
    Color(0xFF00838F), // teal
    Color(0xFF558B2F), // olive
    Color(0xFFAD1457), // magenta
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[seed % _palette.length];
    final letter = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: selected
            ? Border.all(
                color: Theme.of(context).colorScheme.primary, width: 3)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: selected ? 16 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.notoSansTamil(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
