import 'package:supabase_flutter/supabase_flutter.dart';

import '../env/env.dart';

/// Initializes the Supabase client once at startup. After [init] runs,
/// get the client via `Supabase.instance.client` (inject it into
/// controllers/repositories rather than reaching for it from the UI).
abstract final class SupabaseService {
  static Future<void> init() {
    return Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }
}
