import 'package:flutter/material.dart';
import 'friends_screen.dart';

class AmigosTab extends StatelessWidget {
  final bool isGuest;

  const AmigosTab({Key? key, this.isGuest = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Iniciá sesión con tu cuenta de Gameros para ver tus amigos',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
          ),
        ),
      );
    }
    return const FriendsScreen(embedded: true);
  }
}
