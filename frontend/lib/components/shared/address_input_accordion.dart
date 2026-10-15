import 'package:flutter/material.dart';

class AddressInputAccordion extends StatelessWidget {
  final String title;
  final IconData icon;
  final TextEditingController streetController;
  final TextEditingController cityController;
  final TextEditingController stateController;
  final TextEditingController zipController;
  final bool initiallyExpanded;

  const AddressInputAccordion({
    super.key,
    required this.title,
    required this.icon,
    required this.streetController,
    required this.cityController,
    required this.stateController,
    required this.zipController,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    // Own Material so the header's ink splash isn't hidden by decorated
    // parents (e.g. GlassContainer on the profile screen).
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        title: Text(title),
        leading: Icon(icon),
        initiallyExpanded: initiallyExpanded,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextFormField(
            controller: streetController,
            decoration: const InputDecoration(
              labelText: 'Street Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: cityController,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: TextFormField(
                  controller: stateController,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: zipController,
            decoration: const InputDecoration(
              labelText: 'Zip Code',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }
}
