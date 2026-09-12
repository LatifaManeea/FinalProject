import 'fake_repository.dart';
import 'ticked_repository.dart';

/// The single repository instance every screen reads from. Swapping
/// [FakeRepository] for the real Supabase-backed implementation later
/// (Developer A's half of the work split) is a one-line change here —
/// screens only ever import [TickedRepository], never the fake
/// directly, so nothing else needs to change.
final TickedRepository appRepository = FakeRepository();
