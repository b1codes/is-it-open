import 'package:flutter/material.dart';
import 'package:frontend/screens/search/search_screen.dart';
import 'package:frontend/screens/map/map_screen.dart';
import 'package:frontend/screens/places/my_places_screen.dart';
import 'package:frontend/screens/calendar/calendar_screen.dart';
import '../../components/shared/side_menu.dart';
import 'package:frontend/screens/profile/me_screen.dart';
import '../../utils/places_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    MyPlacesScreen(),
    CalendarScreen(),
    MapScreen(),
    SearchScreen(),
    MeScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.places;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 800;

        return Scaffold(
          body: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).scaffoldBackgroundColor,
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    ],
                  ),
                ),
              ),
              if (isMobile)
                _widgetOptions.elementAt(_selectedIndex)
              else
                Row(
                  children: [
                    SideMenu(
                      selectedIndex: _selectedIndex,
                      onIndexChanged: _onItemTapped,
                    ),
                    Expanded(
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body: _widgetOptions.elementAt(_selectedIndex),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          bottomNavigationBar: isMobile
              ? Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: theme.ashSoft,
                        width: 1,
                      ),
                    ),
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _selectedIndex > 4 ? 4 : _selectedIndex,
                    onTap: _onItemTapped,
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: theme.anchor,
                    unselectedItemColor: theme.inkMuted,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    elevation: 0,
                    selectedLabelStyle: PlacesType.label(theme.anchor).copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                    unselectedLabelStyle: PlacesType.label(theme.inkMuted).copyWith(
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.star_rounded),
                        label: 'My Places',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.calendar_month_rounded),
                        label: 'Calendar',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.map_rounded),
                        label: 'Map',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.search_rounded),
                        label: 'Search',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_rounded),
                        label: 'Me',
                      ),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }
}
