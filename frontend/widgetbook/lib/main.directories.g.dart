// dart format width=80
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_import, prefer_relative_imports, directives_ordering

// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AppGenerator
// **************************************************************************

// ignore_for_file: no_leading_underscores_for_library_prefixes

import 'package:widgetbook/widgetbook.dart' as _widgetbook;
import 'package:widgetbook_workspace/use_cases/components/calendar/calendar_event_tile.dart'
    as _widgetbook_workspace_use_cases_components_calendar_calendar_event_tile;
import 'package:widgetbook_workspace/use_cases/components/calendar/calendar_header.dart'
    as _widgetbook_workspace_use_cases_components_calendar_calendar_header;
import 'package:widgetbook_workspace/use_cases/components/calendar/calendar_sidebar.dart'
    as _widgetbook_workspace_use_cases_components_calendar_calendar_sidebar;
import 'package:widgetbook_workspace/use_cases/components/calendar/calendar_view_stack.dart'
    as _widgetbook_workspace_use_cases_components_calendar_calendar_view_stack;
import 'package:widgetbook_workspace/use_cases/components/calendar/event_details_popup.dart'
    as _widgetbook_workspace_use_cases_components_calendar_event_details_popup;
import 'package:widgetbook_workspace/use_cases/components/calendar/planner_view.dart'
    as _widgetbook_workspace_use_cases_components_calendar_planner_view;
import 'package:widgetbook_workspace/use_cases/components/core/refractive_glass.dart'
    as _widgetbook_workspace_use_cases_components_core_refractive_glass;
import 'package:widgetbook_workspace/use_cases/components/places/address_map_thumb.dart'
    as _widgetbook_workspace_use_cases_components_places_address_map_thumb;
import 'package:widgetbook_workspace/use_cases/components/places/quick_add_place_sheet.dart'
    as _widgetbook_workspace_use_cases_components_places_quick_add_place_sheet;
import 'package:widgetbook_workspace/use_cases/components/places/saved_place_views.dart'
    as _widgetbook_workspace_use_cases_components_places_saved_place_views;
import 'package:widgetbook_workspace/use_cases/components/places/status_pill.dart'
    as _widgetbook_workspace_use_cases_components_places_status_pill;
import 'package:widgetbook_workspace/use_cases/components/search/search_result_cards.dart'
    as _widgetbook_workspace_use_cases_components_search_search_result_cards;
import 'package:widgetbook_workspace/use_cases/components/shared/address_input_accordion.dart'
    as _widgetbook_workspace_use_cases_components_shared_address_input_accordion;
import 'package:widgetbook_workspace/use_cases/components/shared/auth0_universal_login_dialog.dart'
    as _widgetbook_workspace_use_cases_components_shared_auth0_universal_login_dialog;
import 'package:widgetbook_workspace/use_cases/components/shared/glass_surfaces.dart'
    as _widgetbook_workspace_use_cases_components_shared_glass_surfaces;
import 'package:widgetbook_workspace/use_cases/components/shared/side_menu.dart'
    as _widgetbook_workspace_use_cases_components_shared_side_menu;
import 'package:widgetbook_workspace/use_cases/components/shared/thermal_button.dart'
    as _widgetbook_workspace_use_cases_components_shared_thermal_button;
import 'package:widgetbook_workspace/use_cases/screens/auth/auth_screens.dart'
    as _widgetbook_workspace_use_cases_screens_auth_auth_screens;
import 'package:widgetbook_workspace/use_cases/screens/calendar/calendar_screen.dart'
    as _widgetbook_workspace_use_cases_screens_calendar_calendar_screen;
import 'package:widgetbook_workspace/use_cases/screens/home/home_screen.dart'
    as _widgetbook_workspace_use_cases_screens_home_home_screen;
import 'package:widgetbook_workspace/use_cases/screens/map/map_screen.dart'
    as _widgetbook_workspace_use_cases_screens_map_map_screen;
import 'package:widgetbook_workspace/use_cases/screens/places/my_places_screen.dart'
    as _widgetbook_workspace_use_cases_screens_places_my_places_screen;
import 'package:widgetbook_workspace/use_cases/screens/places/place_screens.dart'
    as _widgetbook_workspace_use_cases_screens_places_place_screens;
import 'package:widgetbook_workspace/use_cases/screens/profile/profile_screens.dart'
    as _widgetbook_workspace_use_cases_screens_profile_profile_screens;
import 'package:widgetbook_workspace/use_cases/screens/search/search_screen.dart'
    as _widgetbook_workspace_use_cases_screens_search_search_screen;

final directories = <_widgetbook.WidgetbookNode>[
  _widgetbook.WidgetbookFolder(
    name: 'components',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'calendar',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'CalendarEventTileWidget',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Business block',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_event_tile
                        .buildCalendarEventTileBusinessUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Personal event',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_event_tile
                        .buildCalendarEventTilePersonalUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'CalendarHeaderWidget',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_header
                        .buildCalendarHeaderUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'CalendarSidebarWidget',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_sidebar
                        .buildCalendarSidebarUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'CalendarViewStackWidget',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_view_stack
                        .buildCalendarViewStackUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'EventDetailsPopup',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'All-day event',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_event_details_popup
                        .buildEventDetailsPopupAllDayUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Timed event',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_event_details_popup
                        .buildEventDetailsPopupTimedUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'FullDayEventWidget',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Multiple events',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_event_tile
                        .buildFullDayEventMultipleUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Single event',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_calendar_event_tile
                        .buildFullDayEventSingleUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PlannerView',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_planner_view
                        .buildPlannerViewUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Empty',
                builder:
                    _widgetbook_workspace_use_cases_components_calendar_planner_view
                        .buildPlannerViewEmptyUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'core',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'RefractiveGlass',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_core_refractive_glass
                        .buildRefractiveGlassUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'places',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AddressMapThumb',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_places_address_map_thumb
                        .buildAddressMapThumbUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'QuickAddPlaceSheet',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Bottom sheet',
                builder:
                    _widgetbook_workspace_use_cases_components_places_quick_add_place_sheet
                        .buildQuickAddPlaceSheetUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'SavedPlaceRow',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_places_saved_place_views
                        .buildSavedPlaceRowUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'List',
                builder:
                    _widgetbook_workspace_use_cases_components_places_saved_place_views
                        .buildSavedPlaceRowListUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'SavedPlaceTile',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_places_saved_place_views
                        .buildSavedPlaceTileUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Grid',
                builder:
                    _widgetbook_workspace_use_cases_components_places_saved_place_views
                        .buildSavedPlaceTileGridUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'StatusPill',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'All states',
                builder:
                    _widgetbook_workspace_use_cases_components_places_status_pill
                        .buildStatusPillAllStatesUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _widgetbook_workspace_use_cases_components_places_status_pill
                        .buildStatusPillPlaygroundUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'search',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'SearchResultGridCard',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_search_search_result_cards
                        .buildSearchResultGridCardUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Results grid',
                builder:
                    _widgetbook_workspace_use_cases_components_search_search_result_cards
                        .buildSearchResultGridCardGridUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'SearchResultListCard',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_search_search_result_cards
                        .buildSearchResultListCardUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Results list',
                builder:
                    _widgetbook_workspace_use_cases_components_search_search_result_cards
                        .buildSearchResultListCardListUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'shared',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'AddressInputAccordion',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Collapsed',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_address_input_accordion
                        .buildAddressInputAccordionCollapsedUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Expanded, prefilled',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_address_input_accordion
                        .buildAddressInputAccordionExpandedUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'Auth0UniversalLoginDialog',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_auth0_universal_login_dialog
                        .buildAuth0UniversalLoginDialogUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassCard',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_glass_surfaces
                        .buildGlassCardUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'GlassContainer',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_glass_surfaces
                        .buildGlassContainerUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'SideMenu',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_side_menu
                        .buildSideMenuUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'ThermalButton',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_thermal_button
                        .buildThermalButtonUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Disabled',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_thermal_button
                        .buildThermalButtonDisabledUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Loading',
                builder:
                    _widgetbook_workspace_use_cases_components_shared_thermal_button
                        .buildThermalButtonLoadingUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
  _widgetbook.WidgetbookFolder(
    name: 'screens',
    children: [
      _widgetbook.WidgetbookFolder(
        name: 'auth',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'ForgotPasswordScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_auth_auth_screens
                        .buildForgotPasswordScreenUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'LoginScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_auth_auth_screens
                        .buildLoginScreenUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Signing in',
                builder:
                    _widgetbook_workspace_use_cases_screens_auth_auth_screens
                        .buildLoginScreenLoadingUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'RegisterScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Creating account',
                builder:
                    _widgetbook_workspace_use_cases_screens_auth_auth_screens
                        .buildRegisterScreenLoadingUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_auth_auth_screens
                        .buildRegisterScreenUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'calendar',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'CalendarScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_calendar_calendar_screen
                        .buildCalendarScreenUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Loading places',
                builder:
                    _widgetbook_workspace_use_cases_screens_calendar_calendar_screen
                        .buildCalendarScreenLoadingUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'No saved places',
                builder:
                    _widgetbook_workspace_use_cases_screens_calendar_calendar_screen
                        .buildCalendarScreenEmptyUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'home',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'HomeScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Signed in',
                builder:
                    _widgetbook_workspace_use_cases_screens_home_home_screen
                        .buildHomeScreenUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'map',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'MapScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder: _widgetbook_workspace_use_cases_screens_map_map_screen
                    .buildMapScreenUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'No saved places',
                builder: _widgetbook_workspace_use_cases_screens_map_map_screen
                    .buildMapScreenEmptyUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'places',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'CreatePlaceScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildCreatePlaceScreenUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'MyPlacesScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_my_places_screen
                        .buildMyPlacesScreenUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Empty',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_my_places_screen
                        .buildMyPlacesScreenEmptyUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Error',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_my_places_screen
                        .buildMyPlacesScreenErrorUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Loading',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_my_places_screen
                        .buildMyPlacesScreenLoadingUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PlaceDetailScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Custom place, no hours',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenCustomUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Not saved yet',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenUnsavedUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'On today\'s route',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenOnTodayUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Playground',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenPlaygroundUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Saved place',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenSavedUseCase,
              ),
              _widgetbook.WidgetbookUseCase(
                name: 'Split hours',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlaceDetailScreenSplitHoursUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'PlanVisitScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_places_place_screens
                        .buildPlanVisitScreenUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'profile',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'MeScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_profile_profile_screens
                        .buildMeScreenUseCase,
              ),
            ],
          ),
          _widgetbook.WidgetbookComponent(
            name: 'SettingsScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_profile_profile_screens
                        .buildSettingsScreenUseCase,
              ),
            ],
          ),
        ],
      ),
      _widgetbook.WidgetbookFolder(
        name: 'search',
        children: [
          _widgetbook.WidgetbookComponent(
            name: 'SearchScreen',
            useCases: [
              _widgetbook.WidgetbookUseCase(
                name: 'Default',
                builder:
                    _widgetbook_workspace_use_cases_screens_search_search_screen
                        .buildSearchScreenUseCase,
              ),
            ],
          ),
        ],
      ),
    ],
  ),
];
