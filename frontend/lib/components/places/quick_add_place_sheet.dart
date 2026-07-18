import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../services/api_service.dart';
import '../../utils/places_theme.dart';

// Add-a-custom-place sheet. Lightweight: name + address are required; the
// "pick on map" and inline hours editor are flagged as follow-ups so the
// happy path stays under 10 seconds (brief §2).
class QuickAddPlaceSheet extends StatefulWidget {
  const QuickAddPlaceSheet({super.key, this.onSaved});

  final ValueChanged<Place>? onSaved;

  @override
  State<QuickAddPlaceSheet> createState() => _QuickAddPlaceSheetState();
}

class _QuickAddPlaceSheetState extends State<QuickAddPlaceSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final api = context.read<ApiService>();
    final nav = Navigator.of(context);
    final scaffold = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      final place = Place(
        tomtomId: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim(),
        address: _address.text.trim(),
        location: const LatLng(0.0, 0.0),
      );
      final savedPlace = await api.savePlace(place);
      await api.bookmarkPlace(savedPlace.tomtomId);
      widget.onSaved?.call(savedPlace);
      if (mounted) nav.pop(savedPlace);
    } catch (e) {
      scaffold.showSnackBar(SnackBar(content: Text('Couldn\'t save place.')));
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.paperRaised,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(PlacesRadius.lg),
          ),
        ),
        padding: const EdgeInsets.all(PlacesSpacing.lg),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.ash,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: PlacesSpacing.lg),
                  Text('Add a place', style: PlacesType.headline(theme.ink)),
                  const SizedBox(height: PlacesSpacing.xs),
                  Text(
                    "Save somewhere you go. Hours and map location can be filled in later.",
                    style: PlacesType.bodySmall(theme.inkMuted),
                  ),
                  const SizedBox(height: PlacesSpacing.lg),
                  _SheetField(
                    controller: _name,
                    label: 'Name',
                    hint: 'Dad\'s house, the trailhead, etc.',
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Give the place a name.'
                        : null,
                    autofocus: true,
                  ),
                  const SizedBox(height: PlacesSpacing.md),
                  _SheetField(
                    controller: _address,
                    label: 'Address',
                    hint: 'Street and city',
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Add an address.'
                        : null,
                  ),
                  const SizedBox(height: PlacesSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: theme.anchor,
                          borderRadius: BorderRadius.circular(PlacesRadius.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(
                              PlacesRadius.md,
                            ),
                            onTap: _submitting ? null : _submit,
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: _submitting
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation(
                                            theme.anchorOnContrast,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'Save place',
                                        style: TextStyle(
                                          color: theme.anchorOnContrast,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: PlacesSpacing.sm),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.inkMuted,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ],
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

class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      validator: validator,
      style: PlacesType.body(theme.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: PlacesType.body(theme.inkMuted.withValues(alpha: 0.6)),
        labelStyle: PlacesType.label(theme.inkMuted),
        filled: true,
        fillColor: theme.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PlacesRadius.sm),
          borderSide: BorderSide(color: theme.ash),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PlacesRadius.sm),
          borderSide: BorderSide(color: theme.ashSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PlacesRadius.sm),
          borderSide: BorderSide(color: theme.anchor, width: 2),
        ),
        errorStyle: PlacesType.label(theme.closingColor),
      ),
    );
  }
}
