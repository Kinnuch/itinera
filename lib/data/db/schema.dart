/// 建表语句集中在这里，`AppDatabase` 的 onCreate / onUpgrade 都从这里取。
class Schema {
  Schema._();

  static const int version = 1;

  static const List<String> createStatements = [
    '''
    CREATE TABLE trips (
      id            TEXT PRIMARY KEY,
      title         TEXT NOT NULL,
      start_date    TEXT NOT NULL,
      end_date      TEXT NOT NULL,
      home_currency TEXT NOT NULL DEFAULT 'CNY',
      destination   TEXT,
      cover_path    TEXT,
      budget_minor  INTEGER,
      headcount     INTEGER NOT NULL DEFAULT 1,
      note          TEXT,
      updated_at    TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE plan_items (
      id             TEXT PRIMARY KEY,
      trip_id        TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      date           TEXT NOT NULL,
      category       TEXT NOT NULL,
      title          TEXT NOT NULL,
      start_minutes  INTEGER,
      end_minutes    INTEGER,
      place_name     TEXT, place_address TEXT, place_lat REAL, place_lng REAL,
      place_poi_id   TEXT, place_provider TEXT,
      from_name      TEXT, from_address  TEXT, from_lat  REAL, from_lng  REAL,
      from_poi_id    TEXT, from_provider  TEXT,
      to_name        TEXT, to_address    TEXT, to_lat    REAL, to_lng    REAL,
      to_poi_id      TEXT, to_provider    TEXT,
      transport_mode TEXT,
      carrier_no     TEXT,
      amount_minor   INTEGER,
      currency       TEXT,
      headcount      INTEGER NOT NULL DEFAULT 1,
      booked         INTEGER NOT NULL DEFAULT 0,
      booking_ref    TEXT,
      note           TEXT,
      sort_order     INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_items_trip_date ON plan_items(trip_id, date, start_minutes, sort_order)',
    '''
    CREATE TABLE attachments (
      id         TEXT PRIMARY KEY,
      item_id    TEXT NOT NULL REFERENCES plan_items(id) ON DELETE CASCADE,
      bytes      BLOB NOT NULL,
      kind       TEXT NOT NULL DEFAULT 'image',
      mime_type  TEXT NOT NULL DEFAULT 'image/jpeg',
      caption    TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0
    )
    ''',
    'CREATE INDEX idx_attachments_item ON attachments(item_id, sort_order)',
    '''
    CREATE TABLE day_notes (
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      date    TEXT NOT NULL,
      text    TEXT NOT NULL,
      PRIMARY KEY (trip_id, date)
    )
    ''',
    '''
    CREATE TABLE exchange_rates (
      base      TEXT NOT NULL,
      quote     TEXT NOT NULL,
      rate      REAL NOT NULL,
      fetched_at TEXT NOT NULL,
      PRIMARY KEY (base, quote)
    )
    ''',
    // Directions 结果按「起点-终点-方式」缓存，避免每次打开地图都重新请求。
    '''
    CREATE TABLE route_cache (
      cache_key   TEXT PRIMARY KEY,
      polyline    TEXT NOT NULL,
      distance_m  REAL NOT NULL,
      duration_s  INTEGER NOT NULL,
      fetched_at  TEXT NOT NULL
    )
    ''',
  ];
}
