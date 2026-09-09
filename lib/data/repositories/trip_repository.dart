import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/time_utils.dart';
import '../db/database.dart';
import '../models/trip.dart';

class TripRepository {
  TripRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<Trip>> listTrips() async {
    final db = await _db.database;
    final rows = await db.query('trips', orderBy: 'start_date DESC');
    return rows.map(Trip.fromRow).toList();
  }

  Future<Trip?> findTrip(String id) async {
    final db = await _db.database;
    final rows = await db.query('trips', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Trip.fromRow(rows.first);
  }

  Future<Trip> createTrip({
    required String title,
    required DateOnly startDate,
    required DateOnly endDate,
    required String homeCurrency,
    String? destination,
    int? budgetMinor,
    int headcount = 1,
  }) async {
    final trip = Trip(
      id: _uuid.v4(),
      title: title,
      startDate: startDate,
      endDate: endDate,
      homeCurrency: homeCurrency,
      destination: destination,
      budgetMinor: budgetMinor,
      headcount: headcount,
      updatedAt: DateTime.now(),
    );
    final db = await _db.database;
    await db.insert('trips', trip.toRow());
    return trip;
  }

  Future<void> saveTrip(Trip trip) async {
    final db = await _db.database;
    await db.update(
      'trips',
      trip.copyWith(updatedAt: DateTime.now()).toRow(),
      where: 'id = ?',
      whereArgs: [trip.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteTrip(String id) async {
    final db = await _db.database;
    await db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  /// 落在行程日期区间之外的条目——改期后用来提示用户「有 3 项掉到区间外了」。
  Future<int> countOrphanItems(Trip trip) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM plan_items WHERE trip_id = ? AND (date < ? OR date > ?)',
      [trip.id, trip.startDate.toIso(), trip.endDate.toIso()],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// 整体平移行程（出发日改了，所有安排跟着挪）。
  Future<void> shiftTripDates(Trip trip, int days) async {
    if (days == 0) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        "UPDATE plan_items SET date = date(date, ? || ' day') WHERE trip_id = ?",
        [days.toString(), trip.id],
      );
      await txn.rawUpdate(
        "UPDATE day_notes SET date = date(date, ? || ' day') WHERE trip_id = ?",
        [days.toString(), trip.id],
      );
      final moved = trip.copyWith(
        startDate: trip.startDate.addDays(days),
        endDate: trip.endDate.addDays(days),
        updatedAt: DateTime.now(),
      );
      await txn.update('trips', moved.toRow(), where: 'id = ?', whereArgs: [trip.id]);
    });
  }

  Future<Map<String, String>> dayNotes(String tripId) async {
    final db = await _db.database;
    final rows = await db.query('day_notes', where: 'trip_id = ?', whereArgs: [tripId]);
    return {for (final r in rows) r['date'] as String: r['text'] as String};
  }

  Future<void> saveDayNote(DayNote note) async {
    final db = await _db.database;
    if (note.text.trim().isEmpty) {
      await db.delete(
        'day_notes',
        where: 'trip_id = ? AND date = ?',
        whereArgs: [note.tripId, note.date.toIso()],
      );
      return;
    }
    await db.insert('day_notes', note.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
