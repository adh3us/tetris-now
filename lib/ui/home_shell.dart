import 'package:flutter/material.dart';
import 'package:gameros_auth_ui/gameros_auth_ui.dart';
import '../core/supabase_config.dart';
import 'amigos_tab.dart';
import 'jugar_tab.dart';
import 'salas_tab.dart';
import 'tienda_tab.dart';
import 'torneos_tab.dart';

/// Shell de navegación por bloques: Amigos, Jugar, Salas, Torneos, Tienda.
class HomeShell extends StatefulWidget {
  final bool isGuest;
  final VoidCallback? onGuestExit;

  const HomeShell({Key? key, this.isGuest = false, this.onGuestExit}) : super(key: key);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 2; // Arranca en "Jugar"

  static const _titles = ['AMIGOS', 'SALAS', 'JUGAR', 'TORNEOS', 'TIENDA'];

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      AmigosTab(isGuest: widget.isGuest),
      const SalasTab(),
      JugarTab(isGuest: widget.isGuest),
      const TorneosTab(),
      const TiendaTab(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF07090E),
      appBar: AppBar(
        title: Text(
          _titles[_currentIndex],
          style: const TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.w900, fontSize: 13.5, color: Color(0xFFF1F5F9)),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: Color(0xFF94A3B8)),
            tooltip: 'Cerrar Sesión',
            onPressed: () async {
              if (widget.isGuest) {
                widget.onGuestExit?.call();
              } else {
                await GamerosAuthService(supabase: SupabaseConfig.client).signOut();
              }
            },
          ),
        ],
      ),
      body: IndexedStack(index: _currentIndex, children: tabs),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0D111A),
        selectedItemColor: const Color(0xFF818CF8),
        unselectedItemColor: const Color(0xFF64748B),
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.people_alt_rounded), label: 'Amigos'),
          BottomNavigationBarItem(icon: Icon(Icons.meeting_room_rounded), label: 'Salas'),
          BottomNavigationBarItem(icon: Icon(Icons.flash_on_rounded), label: 'Jugar'),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events_rounded), label: 'Torneos'),
          BottomNavigationBarItem(icon: Icon(Icons.storefront_rounded), label: 'Tienda'),
        ],
      ),
    );
  }
}
