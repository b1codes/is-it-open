import 'package:flutter/material.dart';
import 'package:frontend/components/shared/side_menu.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../../mocks/mock_app_scope.dart';
import '../../support/stage.dart';

const _destinations = ['My Places', 'Calendar', 'Map', 'Search', 'Me'];

@widgetbook.UseCase(name: 'Default', type: SideMenu)
Widget buildSideMenuUseCase(BuildContext context) {
  final selectedIndex = context.knobs.int.slider(
    label: 'Selected index',
    initialValue: 2,
    max: _destinations.length - 1,
  );
  return MockAppScope(
    child: Scaffold(
      body: Row(
        children: [
          Builder(
            builder: (context) => SideMenu(
              selectedIndex: selectedIndex,
              onIndexChanged: (index) => logAction(
                context,
                'onIndexChanged($index) → ${_destinations.elementAtOrNull(index) ?? index}',
              ),
            ),
          ),
          const Expanded(child: SizedBox.expand()),
        ],
      ),
    ),
  );
}
