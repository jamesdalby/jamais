import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aisdecode/ais.dart';
import 'package:aisdecode/geom.dart' as geom;

void main() async {
  runApp(AISDisplay());

}

class AISDisplay extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return MaterialApp(
          title: 'AIS Display',
          theme: ThemeData(primarySwatch: Colors.blue),
          home: AISPage(),

    );
  }
}

class AISPage extends StatefulWidget {
  AISPage();
  @override _AISState createState() => _AISState();
}

class AISInfo {
  final int mmsi;
  final String _ship;

  String get ship => _ship??"[$mmsi]";
  double get lat => _them.lat;
  double get lon => _them.lon;
  double get cog => _them.cog;
  double get sog => _them.sog;

  double get range => _range;
  double get t => _t;
  double get d => _d;
  int get bearing => _bearing;

  double _range;
  int _bearing;
  double _t;
  double _d;
  final PCS _them;

  AISInfo(this.mmsi, this._ship, PCS us, this._them) {
    _revise(us);
  }

  void _revise(final PCS us) {
    _range = geom.range(us.lat, us.lon, _them.lat, _them.lon);
    _bearing = geom.bearing(us.lat, us.lon, _them.lat, _them.lon).toInt();
    _t = tcpa(us, _them);
    _d = cpa(us, _them, _t);
  }

  @override
  String toString() {
    return 'AISInfo{mmsi: $mmsi, ship: $ship, range: $range, bearing: $bearing, t: $t mins, d: $d nm}';
  }

}

class MyAISHandler extends AISHandler {
  _AISState _state;
  MyAISHandler(String host, int port, this._state) : super(host, port);

  @override
  void they(PCS us, PCS them, int mmsi) {
    _state.add(
        AISInfo(mmsi, name(mmsi), us, them)
    );
  }

  PCS _usCalc;  // the version of _us used for calculations of CPA/TCP

  @override
  void we(PCS us) {
    // Our position, course, speed has changed.
    // If the change is beyond some threshold since last change was detected, then
    // recompute the CPA, TCPA, Range and Bearing of all known targets.
    // This is a fairly expensive operation, particularly if there is a large number of active targets,
    // so we strive to reduce the number of times it's done to a sensible level, without compromising
    // the usefulness of the results
    if (_needsRecalc(_usCalc, us)) {
      _state.revise(us);
      _usCalc = us;
    }
  }

  bool _needsRecalc(PCS prev, PCS curr) {
    if (prev == null) { return true; }
    if (distance(prev,curr,0) > 0.02) {
      return true;
    }
    if ((prev.cog-curr.cog).abs() > 3) { return true; }

    return false;
  }
}

class AISSharedPreferences {
  String _host;
  int _port;
  double _cpa;
  double _tcpa;
  int _maxTargets;
  bool _hideDivergent;
  static SharedPreferences _prefs;

  static const String aisHost = 'ais.host';
  static const String aisPort = 'ais.port';
  static const String aisCPA = 'ais.CPA';
  static const String aisTCPA = 'ais.TCPA';
  static const String aisMaxTargets = 'ais.maxTargets';
  static const String aisHideDivergent = 'ais.hideDivergent';

  set host(String h) => _host = _set(aisHost, _prefs.setString, h);
  set port(int h) => _port = _set(aisPort, _prefs.setInt, h);
  set cpa(double h) => _cpa = _set(aisCPA, _prefs.setDouble, h);
  set tcpa(double h) => _tcpa = _set(aisTCPA, _prefs.setDouble, h);
  set maxTargets(int h) => _maxTargets = _set(aisMaxTargets, _prefs.setInt, h);
  set hideDivergent(bool h) => _hideDivergent = _set(aisHideDivergent, _prefs.setBool, h);


  static Future<AISSharedPreferences> instance() async {
    _prefs = await SharedPreferences.getInstance();
      return AISSharedPreferences(
          _prefs.get(aisHost) ?? 'localhost',
          _prefs.get(aisPort) ?? 10110,
          _prefs.get(aisCPA),
          _prefs.get(aisTCPA),
          _prefs.get(aisMaxTargets) ?? 20,
          _prefs.get(aisHideDivergent) ?? true
      );

  }

  AISSharedPreferences(this._host, this._port, this._cpa, this._tcpa,
      this._maxTargets, this._hideDivergent);

   T _set<T>(String s, Future<bool> Function(String key, T value) setter, T h) {
    setter(s, h);
    return h;
  }

  String get host => _host??'localhost';
  int get port => _port??10110;
  double get cpa => _cpa;
  double get tcpa => _tcpa;
  int get maxTargets => _maxTargets??10;
  bool get hideDivergent => _hideDivergent??true;
}

class _AISState extends State<AISPage> {
  Set<AISInfo> them = SplayTreeSet((a,b)=>a.mmsi.compareTo(b.mmsi));
  AISSharedPreferences _prefs;
  MyAISHandler _aisHandler;
  Function _builder;
  
  _AISState() {
    AISSharedPreferences.instance().then((p) {
      _prefs = p;
      _aisHandler = MyAISHandler(_prefs.host, _prefs.port, this);
     _aisHandler.run();
    });
    _builder = buildGraphic;
  }

  void revise(PCS us) {
    them.forEach((f)=>f._revise(us));
    setState(()=>{});
  }

  void add(AISInfo info) {
    setState(() {
      them.remove(info);
      them.add(info);
    });
  }

  String _hms(double v) {
    if (v == null || v.isInfinite || v.isNaN) { return '??:??:??'; }
    int h = v.toInt();
    int m = (v*60).toInt() % 60;
    int s = (v*3600).toInt() % 60;
    return
          h.toString().padLeft(2,'0') + ":" +
          m.toString().padLeft(2,'0') + ":" +
          s.toString().padLeft(2,'0');
  }

  bool _show(final AISInfo a) {
    if ((_prefs.hideDivergent??true) && (a.t <= 0)) { return false; }
    if ((_prefs.cpa??double.infinity) < a.d) { return false; }
    if ((_prefs.tcpa??double.infinity) < (a.t*60)) { return false; }
    return true;
  }

  List<DataRow> _themCells() {
    List<AISInfo> l = them.toList();
    l.sort((a,b)=>a.d.compareTo(b.d));
    return l
        .where(_show)
        .take(_prefs?.maxTargets??10)
        .map((v)=>
          DataRow(
            cells: [
             DataCell(Text(v.ship)),
             DataCell(Text((v.range?.toStringAsFixed(1)??'') + "\n" + (v.bearing.toString()??''), textAlign: TextAlign.right)),
             DataCell(Text((v.sog?.toStringAsFixed(1)??'') + "\n" + (v.cog?.toStringAsFixed(0)??''), textAlign: TextAlign.right)),
             DataCell(Text(v.d?.toStringAsFixed(1)??'?', textAlign: TextAlign.right)),
             DataCell(Text(_hms(v.t), textAlign: TextAlign.right)),
            // sog, cog, lat, lon
            ]
          )
    ).toList();
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('AIS'),
      ),
      drawer: Drawer(
          child: ListView(children: <Widget>[
            ListTile(
                title: Text('Communications'),
                onTap: () async {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (BuildContext context) => CommsSettings(
                            _prefs
                          ))
                  ).then((var s) async {
                    // print("$s ${s.host}:${s.port}");
                    _prefs.host = s.host;
                    _prefs.port = s.port;
                    _aisHandler.setSource(s.host, s.port);
                  });
                }),
            ListTile(
                title: Text('AIS parameters'),
                onTap: () async {
                  Navigator.of(context).pop();
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (BuildContext context) => AISSettings(_prefs))
                  ).then((var s) {
                    _prefs.maxTargets = s.maxTargets;
                    _prefs.cpa = s.cpa;
                    _prefs.tcpa = s.tcpa;
                    _prefs.hideDivergent = s.hideDivergent;
                  });
                })
          ])),
      body: _builder(/* _aisHandler._usCalc, them, _prefs*/)
    );
  }

  Widget buildGraphic(/*PCS us, List<PCS> them, AISSharedPreferences prefs*/) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return new CustomPaint(
          size: constraints.biggest,
          painter: AISPainter(_aisHandler?._usCalc, them, _prefs)

        );
      }

    );

  }

  Widget buildList(PCS us, List<PCS> them, AISSharedPreferences prefs) {
    return SingleChildScrollView(
      child: DataTable(
        horizontalMargin: 3,
        columnSpacing: 3,

        columns: [
          DataColumn(label:Text('ID')),
          DataColumn(label:Text('Range (nm)\nBearing°', textAlign: TextAlign.right), numeric: true),
          DataColumn(label:Text('SOG (kn)\nCOG°', textAlign: TextAlign.right), numeric: true),
          DataColumn(label:Text('CPA\n(nm)', textAlign: TextAlign.right), numeric: true),
          DataColumn(label:Text('TCPA\n(hh:mm:ss)', textAlign: TextAlign.right), numeric: true),
          // sog, cog, lat, lon
        ],
        rows: _themCells()
      ),
    );
  }

}

class AISPainter extends CustomPainter {
  final PCS us;
  final Set<AISInfo> them;
  final AISSharedPreferences prefs;

  AISPainter(this.us, this.them, this.prefs) {

  }


  
  @override
  void paint(Canvas canvas, Size size) {
    Paint p = Paint();
    p.style = PaintingStyle.stroke;

    // 0,0 is top left corner

    Path path = Path();
    path.moveTo(0, 0);
    path.lineTo(.5, -1);
    path.lineTo(-.5, -1);
    path.lineTo(0, 0);
    path.lineTo(0, 1+ (us?.sog??0) / 5);

    path = path.transform(Matrix4.diagonal3Values(size.width/20,size.height/20,1).storage);
    path = path.transform(Matrix4.rotationZ(rad(us?.cog??0)).storage);
    path = path.transform(Matrix4.translationValues(size.width/2, size.height/2, 0).storage);



    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}

class _CommsSettingsState extends State<CommsSettings> {
  TextEditingController _hc;
  TextEditingController _pc;

  _CommsSettingsState(final AISSharedPreferences prefs) :
    _hc = TextEditingController(text: prefs.host),
    _pc = TextEditingController(text: prefs.port.toString()); // TODO input type restrictions

  String get host => _hc.text..trim();
  int get port => int.parse(_pc.text..trim());

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Settings')),
        body: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextFormField(
                controller: _hc,
                decoration: InputDecoration(
                    counterText: 'Hostname or IP address',
                    hintText: 'Hostname'
                ),
                validator: (value) {
                  if (value.isEmpty) {
                    return 'Please enter some text';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _pc,
                decoration: InputDecoration(
                    counterText: 'Port number',
                    hintText: 'Port number'
                ),
                validator: (value) {
                  try {
                    if (int.parse(value) > 0) {
                      return null;
                    }
                  } catch (err) {}
                  return 'Please enter positive number';
                },
              ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: RaisedButton(
                  onPressed: () {
                    if (_formKey.currentState.validate() == true) {
                      Navigator.of(context).pop(this);
                    }
                  },
                  child: Text('Submit'),
                ),
              ),
            ],
          ),
        ));
  }
}

class CommsSettings extends StatefulWidget {
  final AISSharedPreferences _prefs;

  const CommsSettings(this._prefs);

  @override State<CommsSettings> createState() => _CommsSettingsState(this._prefs);
}

class AISSettings extends StatefulWidget {
  final AISSharedPreferences _prefs;
  AISSettings(this._prefs);

  @override State<StatefulWidget> createState() => _AISSettingsState(_prefs);
}

class _AISSettingsState extends State<AISSettings>{
  final _formKey = GlobalKey<FormState>();
  final AISSharedPreferences _prefs;
  TextEditingController _targetsMax;
  TextEditingController _maxCPA;
  TextEditingController _maxTCPA;
  bool _hideDivergent;

  double get cpa => double.tryParse(_maxCPA.text)??null;
  double get tcpa => double.tryParse(_maxTCPA.text)??null;
  int get maxTargets => int.parse(_targetsMax.text);
  bool get hideDivergent => _hideDivergent;

  @override
  void initState() {
    super.initState();
    _targetsMax = TextEditingController(text: _prefs.maxTargets.toString());
    _maxCPA = TextEditingController(text: (_prefs.cpa ?? '').toString());
    _maxTCPA = TextEditingController(text: (_prefs.tcpa ?? '').toString());
    _hideDivergent = _prefs.hideDivergent;
  }

  _AISSettingsState(this._prefs);

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextFormField(
              controller: _targetsMax,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                WhitelistingTextInputFormatter.digitsOnly
              ],
              decoration: InputDecoration(
                labelText: "Max targets to display",
              ),
              validator: (value) {
                int v = int.tryParse(value);
                if (v == null || v < 1) {
                  return 'Please enter a positive integer';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _maxCPA,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                WhitelistingTextInputFormatter(RegExp(r'[.0-9]'))
              ],
              decoration: InputDecoration(
                  labelText: 'Max CPA (nm)',
                  hintText: r'no limit'
              ),
              validator: (String value) {
                if (value == null || value.trim().length == 0) {
                  return null;
                }
                double v = double.tryParse(value);
                if (v == null || v <= 0) {
                  return 'Please enter a positive number (or blank for no limit)';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _maxTCPA,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                WhitelistingTextInputFormatter(RegExp(r'[.0-9]'))
              ],
              decoration: InputDecoration(
                  labelText: 'Max TCPA (minutes)',
                  hintText: r'no limit'
              ),
              validator: (value) {
                if (value == null || value.trim().length == 0) {
                  return null;
                }
                double v = double.tryParse(value);
                if (v == null || v <= 0) {
                  return 'Please enter a positive number (or blank for no limit)';
                }
                return null;
              },
            ),
            InputDecorator(
              child: Center(
                child: Row(
                    children:[
                      Text('Show'),
                      Switch(
                        value: _hideDivergent,
                        onChanged: (value) {
                          setState(() {
                           _hideDivergent = value;
                          });
                        }),
                      Text('Hide')
                  ])),
              decoration: InputDecoration(
                labelText: 'Diverging targets',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: RaisedButton(
                onPressed: () {
                  if (_formKey.currentState.validate() == true) {
                    Navigator.of(context).pop(this);
                  }
                },
                child: Text('Submit'),
              ),
            ),

          ],
        ),
      ),
    );
    }
}

