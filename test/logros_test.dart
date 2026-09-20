import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/services/logros_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('Sistema de Logros - Modelos y Catálogo Local', () {
    test('LogroItem mapea correctamente desde formato Map', () {
      final map = {
        'id': 'primer_tetris',
        'titulo': '¡Tetris Limpio!',
        'descripcion': 'Limpia 4 líneas simultáneas con una sola pieza I.',
        'icono': 'flash_on',
        'categoria': 'habilidad',
        'puntos': 10,
        'orden': 1,
      };

      final logro = LogroItem.fromMap(map, desbloqueado: true);
      expect(logro.id, 'primer_tetris');
      expect(logro.titulo, '¡Tetris Limpio!');
      expect(logro.desbloqueado, true);
      expect(logro.puntos, 10);
      expect(logro.categoria, 'habilidad');
    });

    test('LogrosService contiene catálogo de respaldo completo', () async {
      final service = LogrosService();
      // En entorno de tests unitarios (sin conexión activa a Supabase), devuelve el catálogo seguro
      final logros = await service.getLogrosConEstadoUsuario();
      expect(logros.isNotEmpty, true);
      expect(logros.any((l) => l.id == 'primer_tetris'), true);
      expect(logros.any((l) => l.id == 'cubo_dorado'), true);
      expect(logros.any((l) => l.id == 'cubo_plata'), true);
      expect(logros.any((l) => l.id == 'maestro_srs'), true);
    });
  });
}
