import 'package:flutter/material.dart';
import 'package:frontend/components/shared/address_input_accordion.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../support/stage.dart';

@widgetbook.UseCase(name: 'Collapsed', type: AddressInputAccordion)
Widget buildAddressInputAccordionCollapsedUseCase(BuildContext context) {
  return const ComponentStage(
    child: _AccordionHost(
      title: 'Home Address',
      icon: Icons.home_outlined,
      initiallyExpanded: false,
    ),
  );
}

@widgetbook.UseCase(name: 'Expanded, prefilled', type: AddressInputAccordion)
Widget buildAddressInputAccordionExpandedUseCase(BuildContext context) {
  return const ComponentStage(
    child: _AccordionHost(
      title: 'Work Address',
      icon: Icons.work_outline,
      initiallyExpanded: true,
      street: '1 World Trade Center',
      city: 'New York',
      state: 'NY',
      zip: '10007',
    ),
  );
}

// Owns the TextEditingControllers the accordion expects from its parent form.
class _AccordionHost extends StatefulWidget {
  const _AccordionHost({
    required this.title,
    required this.icon,
    required this.initiallyExpanded,
    this.street = '',
    this.city = '',
    this.state = '',
    this.zip = '',
  });

  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final String street;
  final String city;
  final String state;
  final String zip;

  @override
  State<_AccordionHost> createState() => _AccordionHostState();
}

class _AccordionHostState extends State<_AccordionHost> {
  late final _street = TextEditingController(text: widget.street);
  late final _city = TextEditingController(text: widget.city);
  late final _state = TextEditingController(text: widget.state);
  late final _zip = TextEditingController(text: widget.zip);

  @override
  void dispose() {
    _street.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: AddressInputAccordion(
        title: widget.title,
        icon: widget.icon,
        initiallyExpanded: widget.initiallyExpanded,
        streetController: _street,
        cityController: _city,
        stateController: _state,
        zipController: _zip,
      ),
    );
  }
}
