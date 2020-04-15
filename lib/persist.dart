import 'package:sqflite/sqflite.dart';

class Persist {
  Database _db;

  Persist(this._db);

  static void _createDB(Database db, int version) async {
    await db.execute(
        'CREATE TABLE boatName (mmsi INTEGER PRIMARY KEY, name TEXT)'
    );
  }

  static Future<Database> openDB() async {
    final String p = await getDatabasesPath();
    Database db = await openDatabase(

        "$p/ais.db",
        version: 1,

        onCreate: _createDB
    );
    return db;
  }

  void replace(final int mmsi, final String name) async {
    return await _db.transaction((txn) async {
      return await txn.rawInsert(
          'REPLACE INTO boatName(mmsi, name) VALUES(?,?)',
          [ mmsi, name ]
      );
    });
  }

  Future<Map<int,String>> names() {
    return _db.rawQuery('SELECT * FROM boatName').then(
            (l) => Map.fromIterable(
            l,
            key:     (m)=> m['mmsi'],
            value:   (m)=> m['name']
        )
    );
  }
}

/*

void main() {
  Persist.openDB().then((db) async {
    Persist p = Persist(db);

    p.replace(1234, "OneTwoThreeFour");
    p.replace(56, "FiveSix");

    Map<int, String> m = await p.names();
    print(m.toString());
  });
}*/
