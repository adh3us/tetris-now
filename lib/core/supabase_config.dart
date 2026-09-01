import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String projectId = 'bgwvtfgwhpinfotzyucn';
  static const String supabaseUrl = 'https://bgwvtfgwhpinfotzyucn.supabase.co';
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_VY9KT3GCTt7yeiYJUNCxYA_qnOkOQ6_',
  );

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
