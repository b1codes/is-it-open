import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/bloc/map/map_ui_state.dart';
import 'package:frontend/bloc/map/map_ui_cubit.dart';

void main() {
  test('MapUiState default is sidebar not collapsed', () {
    const state = MapUiState();
    expect(state.isSidebarCollapsed, false);
  });

  test('MapUiCubit toggles state correctly', () {
    final cubit = MapUiCubit();
    cubit.toggleSidebar();
    expect(cubit.state.isSidebarCollapsed, true);
    cubit.toggleSidebar();
    expect(cubit.state.isSidebarCollapsed, false);
  });
}
