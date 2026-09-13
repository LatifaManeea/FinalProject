import 'supabase_repository.dart';
import 'ticked_repository.dart';

/// The single repository instance every screen reads from.
///
/// This used to point at a `FakeRepository` full of seeded films,
/// branches and history — the proposal's day-1 pattern, so the screens
/// could be built before the backend existed. That file is gone: the
/// app now reads and writes the real Supabase project for everything,
/// through the same frozen [TickedRepository] contract, and no screen
/// changed when it was swapped.
final TickedRepository appRepository = SupabaseRepository();
