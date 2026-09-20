import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

enum UserPresenceStatus {
  online,   // Conectado (Verde)
  away,     // Ausente (Amarillo)
  offline,  // Desconectado (Rojo)
}

/// Widget reutilizable que renderiza el punto de estado de conexión al lado del nickname
class UserStatusDot extends StatelessWidget {
  final UserPresenceStatus status;
  final double size;

  const UserStatusDot({
    Key? key,
    required this.status,
    this.size = 8.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;

    switch (status) {
      case UserPresenceStatus.online:
        color = const Color(0xFF22C55E); // Verde vibrante
        tooltip = 'Conectado';
        break;
      case UserPresenceStatus.away:
        color = const Color(0xFFFACC15); // Amarillo Citrino
        tooltip = 'Ausente';
        break;
      case UserPresenceStatus.offline:
        color = const Color(0xFFEF4444); // Rojo
        tooltip = 'Desconectado';
        break;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.65),
              blurRadius: 4,
              spreadRadius: 0.8,
            ),
          ],
        ),
      ),
    );
  }
}

/// Servicio singleton que gestiona la presencia global en Supabase Realtime
class PresenceService with WidgetsBindingObserver {
  static final PresenceService instance = PresenceService._internal();
  PresenceService._internal();

  RealtimeChannel? _presenceChannel;
  String? _currentUserId;
  String? _currentGamerTag;
  UserPresenceStatus _myStatus = UserPresenceStatus.online;

  final ValueNotifier<Map<String, UserPresenceStatus>> statusesNotifier =
      ValueNotifier<Map<String, UserPresenceStatus>>({});

  bool _isInitialized = false;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopTracking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setStatus(UserPresenceStatus.online);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      setStatus(UserPresenceStatus.away);
    } else if (state == AppLifecycleState.detached) {
      setStatus(UserPresenceStatus.offline);
    }
  }

  void startTracking({required String userId, required String gamerTag}) {
    initialize();
    _currentUserId = userId;
    _currentGamerTag = gamerTag;
    _setupPresenceChannel();
  }

  void _setupPresenceChannel() {
    if (_presenceChannel != null) return;
    try {
      final client = SupabaseConfig.client;
      _presenceChannel = client.channel('presence:global');

      _presenceChannel!.onPresenceSync((_) {
        _syncPresenceState();
      });

      _presenceChannel!.onPresenceJoin((_) {
        _syncPresenceState();
      });

      _presenceChannel!.onPresenceLeave((_) {
        _syncPresenceState();
      });

      _presenceChannel!.subscribe((status, [error]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await _trackSelf();
        }
      });
    } catch (_) {}
  }

  Future<void> _trackSelf() async {
    if (_presenceChannel == null || _currentUserId == null) return;
    try {
      final statusStr = _myStatus == UserPresenceStatus.online
          ? 'online'
          : (_myStatus == UserPresenceStatus.away ? 'away' : 'offline');

      await _presenceChannel!.track({
        'user_id': _currentUserId,
        'gamer_tag': _currentGamerTag,
        'status': statusStr,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  void setStatus(UserPresenceStatus newStatus) {
    _myStatus = newStatus;
    _trackSelf();
  }

  void _syncPresenceState() {
    if (_presenceChannel == null) return;
    final Map<String, UserPresenceStatus> newMap = {};
    try {
      final dynamic state = _presenceChannel!.presenceState();
      if (state is Map) {
        state.forEach((key, val) {
          _extractPresenceItem(val, newMap);
        });
      } else if (state is Iterable) {
        for (final item in state) {
          _extractPresenceItem(item, newMap);
        }
      }
    } catch (_) {}

    statusesNotifier.value = newMap;
  }

  void _extractPresenceItem(dynamic val, Map<String, UserPresenceStatus> map) {
    if (val == null) return;
    if (val is Iterable) {
      for (final item in val) {
        _extractPresenceItem(item, map);
      }
      return;
    }
    try {
      String? uId;
      String? st;
      if (val is Map) {
        uId = val['user_id']?.toString();
        st = val['status']?.toString();
      } else {
        final dynamic payload = (val as dynamic).payload;
        if (payload is Map) {
          uId = payload['user_id']?.toString();
          st = payload['status']?.toString();
        }
      }

      if (uId != null && uId.isNotEmpty) {
        if (st == 'away') {
          map[uId] = UserPresenceStatus.away;
        } else if (st == 'offline') {
          map[uId] = UserPresenceStatus.offline;
        } else {
          map[uId] = UserPresenceStatus.online;
        }
      }
    } catch (_) {}
  }

  UserPresenceStatus getStatusForUser(
    String userId, {
    String? dbEstado,
    DateTime? dbUpdatedAt,
  }) {
    // Si soy yo mismo y estoy activo en la app
    if (_currentUserId != null && _currentUserId == userId) {
      return _myStatus;
    }

    // 1. Prioridad: Presencia en tiempo real en el canal
    final live = statusesNotifier.value[userId];
    if (live != null) {
      return live;
    }

    // 2. Base de datos: estado_juego o última conexión
    if (dbEstado != null && dbEstado.trim().isNotEmpty) {
      final s = dbEstado.toLowerCase();
      if (s.contains('ausente') || s.contains('away') || s.contains('idle')) {
        return UserPresenceStatus.away;
      }
      if (s.contains('desconectado') || s.contains('offline')) {
        return UserPresenceStatus.offline;
      }
      if (s.contains('tetris') || s.contains('hub') || s.contains('online') || s.contains('conectado')) {
        return UserPresenceStatus.online;
      }
    }

    // 3. Chequeo por marca temporal (últimos 5 minutos = online, 5-20 = away, >20 = offline)
    if (dbUpdatedAt != null) {
      final diff = DateTime.now().difference(dbUpdatedAt);
      if (diff.inMinutes < 5) {
        return UserPresenceStatus.online;
      } else if (diff.inMinutes < 20) {
        return UserPresenceStatus.away;
      } else {
        return UserPresenceStatus.offline;
      }
    }

    return UserPresenceStatus.offline;
  }

  void _stopTracking() {
    try {
      _presenceChannel?.unsubscribe();
      _presenceChannel = null;
    } catch (_) {}
  }
}
