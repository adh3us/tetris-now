import 'package:flutter/material.dart';

/// Bloque "Salas" — reservado para una futura versión (por ejemplo, listado
/// de salas privadas públicas para mirar/unirse sin invitación directa).
class SalasTab extends StatelessWidget {
  const SalasTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.meeting_room_rounded, size: 48, color: Colors.white24),
            SizedBox(height: 12),
            Text(
              'SALAS',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.2),
            ),
            SizedBox(height: 8),
            Text(
              'Próximamente',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
