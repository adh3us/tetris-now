import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_config.dart';

class FriendModel {
  final String friendshipId;
  final String userId;
  final String gamerTag;
  final String? username;
  final String? avatarUrl;
  final String status; // 'en_linea', 'en_partida', 'desconectado'
  final String currentGame; // 'Tetris Now', 'TrucoArg', 'Chess in Time', 'En el Hub de Gameros', 'Desconectado'
  final int tetrisElo;

  FriendModel({
    required this.friendshipId,
    required this.userId,
    required this.gamerTag,
    this.username,
    this.avatarUrl,
    this.status = 'en_linea',
    this.currentGame = 'Tetris Now',
    this.tetrisElo = 1000,
  });
}

class FriendRequestModel {
  final String requestId;
  final String senderId;
  final String senderGamerTag;
  final String? senderAvatar;
  final DateTime createdAt;

  FriendRequestModel({
    required this.requestId,
    required this.senderId,
    required this.senderGamerTag,
    this.senderAvatar,
    required this.createdAt,
  });
}

class FriendMessageModel {
  final String id;
  final String senderId;
  final String senderGamerTag;
  final String receiverId;
  final String message;
  final DateTime createdAt;
  final bool isRead;

  FriendMessageModel({
    required this.id,
    required this.senderId,
    required this.senderGamerTag,
    required this.receiverId,
    required this.message,
    required this.createdAt,
    this.isRead = false,
  });
}

class FriendsService {
  SupabaseClient get supabase => SupabaseConfig.client;

  Future<List<FriendModel>> getFriends() async {
    final user = supabase.auth.currentUser;
    if (user == null) return _getDemoFriends();

    try {
      final res = await supabase
          .from('amigos')
          .select()
          .or('solicitante_id.eq.${user.id},receptor_id.eq.${user.id}')
          .eq('estado', 'aceptada');

      final List<FriendModel> friends = [];
      for (final row in (res as List)) {
        final friendUserId = row['solicitante_id'] == user.id ? row['receptor_id'] : row['solicitante_id'];
        
        String tag = 'Amigo Gamer';
        String? username;
        String? avatar;
        String game = 'En el Hub de Gameros';
        int elo = 1000;

        try {
          final uRow = await supabase.from('usuarios').select().eq('id', friendUserId).maybeSingle();
          if (uRow != null) {
            tag = uRow['nombre'] ?? uRow['gamertag'] ?? tag;
            username = uRow['username'] ?? uRow['nombre_usuario'];
            avatar = uRow['foto_url'] ?? uRow['avatar_url'];
            game = uRow['estado_juego'] ?? uRow['juego_actual'] ?? 'En el Hub de Gameros';
          }
        } catch (_) {}

        try {
          final rRow = await supabase.schema('tetris').from('ratings').select('rating').eq('user_id', friendUserId).maybeSingle();
          if (rRow != null) elo = rRow['rating'] as int? ?? 1000;
        } catch (_) {}

        friends.add(FriendModel(
          friendshipId: row['id'] as String,
          userId: friendUserId as String,
          gamerTag: tag,
          username: username,
          avatarUrl: avatar,
          status: game == 'Desconectado' ? 'desconectado' : 'en_linea',
          currentGame: game,
          tetrisElo: elo,
        ));
      }

      return friends.isNotEmpty ? friends : _getDemoFriends();
    } catch (_) {
      return _getDemoFriends();
    }
  }

  Future<List<FriendRequestModel>> getPendingRequests() async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await supabase
          .from('amigos')
          .select()
          .eq('receptor_id', user.id)
          .eq('estado', 'pendiente');

      final List<FriendRequestModel> list = [];
      for (final row in (res as List)) {
        final senderId = row['solicitante_id'] as String;
        String tag = 'Jugador Gameros';
        String? avatar;
        try {
          final uRow = await supabase.from('usuarios').select().eq('id', senderId).maybeSingle();
          if (uRow != null) {
            tag = uRow['nombre'] ?? uRow['gamertag'] ?? tag;
            avatar = uRow['foto_url'] ?? uRow['avatar_url'];
          }
        } catch (_) {}

        list.add(FriendRequestModel(
          requestId: row['id'] as String,
          senderId: senderId,
          senderGamerTag: tag,
          senderAvatar: avatar,
          createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
        ));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<bool> sendFriendRequest(String query) async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;

    try {
      final targetUser = await supabase
          .from('usuarios')
          .select('id')
          .or('gamertag.ilike.%$query%,nombre.ilike.%$query%,email.ilike.%$query%,username.ilike.%$query%')
          .maybeSingle();

      if (targetUser == null) return false;
      final targetId = targetUser['id'] as String;
      if (targetId == user.id) return false;

      await supabase.from('amigos').upsert({
        'solicitante_id': user.id,
        'receptor_id': targetId,
        'estado': 'pendiente',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> respondToRequest(String requestId, bool accept) async {
    try {
      await supabase.from('amigos').update({
        'estado': accept ? 'aceptada' : 'rechazada',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
    } catch (_) {}
  }

  Future<void> sendDirectMessage(String receiverId, String text) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('mensajes_amigos').insert({
        'emisor_id': user.id,
        'receptor_id': receiverId,
        'mensaje': text,
      });
    } catch (_) {}
  }

  Future<List<FriendMessageModel>> getDirectMessages(String friendUserId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return [];

    try {
      final res = await supabase
          .from('mensajes_amigos')
          .select()
          .or('and(emisor_id.eq.${user.id},receptor_id.eq.$friendUserId),and(emisor_id.eq.$friendUserId,receptor_id.eq.${user.id})')
          .order('created_at', ascending: true)
          .limit(50);

      return (res as List).map((m) {
        return FriendMessageModel(
          id: m['id'] as String,
          senderId: m['emisor_id'] as String,
          senderGamerTag: m['emisor_id'] == user.id ? 'Tú' : 'Amigo',
          receiverId: m['receptor_id'] as String,
          message: m['mensaje'] as String,
          createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          isRead: m['leido'] as bool? ?? false,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  List<FriendModel> _getDemoFriends() {
    return [
      FriendModel(friendshipId: 'f1', userId: 'lucas_1', gamerTag: 'Lucas', username: '@Lucas', status: 'en_linea', currentGame: 'Jugando Tetris Now', tetrisElo: 1048),
      FriendModel(friendshipId: 'f2', userId: 'matias_2', gamerTag: 'Matias_Pro', username: '@Matias', status: 'en_linea', currentGame: 'Jugando TrucoArg', tetrisElo: 1120),
      FriendModel(friendshipId: 'f3', userId: 'valen_3', gamerTag: 'Valen_Chess', username: '@Valen', status: 'en_linea', currentGame: 'Jugando Chess in Time', tetrisElo: 1250),
      FriendModel(friendshipId: 'f4', userId: 'nico_4', gamerTag: 'NicoGamer', username: '@Nico', status: 'en_linea', currentGame: 'En el Hub de Gameros', tetrisElo: 1000),
    ];
  }
}
