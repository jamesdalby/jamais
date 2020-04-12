import 'dart:collection';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aisdecode/ais.dart';
import 'package:aisdecode/geom.dart' as geom;

import 'dart:ui' as ui show TextStyle;

import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() async {
  runApp(AISDisplay());

}

class AISDisplay extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return MaterialApp(
          title: 'JamAIS',
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
  PCS get pcs => _them;

  double get range => _range;
  double get t => _t;
  double get d => _d;
  int get bearing => _bearing;

  double _range;
  int _bearing;
  double _t;
  double _d;
  final PCS _them;

  Map<int,AIS> get ais => _aisMap;

  final Map<int,AIS> _aisMap;

  AISInfo(this.mmsi, this._ship, PCS us, this._them, this._aisMap) {
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
        AISInfo(mmsi, name(mmsi), us, them, getMostRecentMessages(mmsi))
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

  AISSharedPreferences(this._host, this._port, this._cpa, this._tcpa, this._maxTargets, this._hideDivergent);

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
  bool showList = true;
  
  _AISState() {
    // be careful, _prefs might take time to become established
    AISSharedPreferences.instance().then((p) {
      _prefs = p;
      _aisHandler = MyAISHandler(_prefs.host, _prefs.port, this);
     _aisHandler.run();
    });
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
                  DataCell(GestureDetector(
                    onTap:  () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (BuildContext context) => AISDetails([v.ais]))
                    ),
                    child: Text(v.ship),

                  )),
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
                    if (s != null) {
                      _prefs.maxTargets = s.maxTargets;
                      _prefs.cpa = s.cpa;
                      _prefs.tcpa = s.tcpa;
                      _prefs.hideDivergent = s.hideDivergent;
                    }
                  });
                }),
            ListTile(
                title: Text('List view'),
                onTap: () {
                  showList = true;
                  Navigator.of(context).pop();
                }
            ),
            ListTile(
              title: Text('Schematic view'),
              onTap: () {
                showList = false;
                Navigator.of(context).pop();
              }
            )

          ])),
      body: showList ? buildList() : buildGraphic()
    );
  }


  double scale = 1;
  double scale2 = 1;

  Widget buildGraphic() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final AISPainter aisPainter = AISPainter(_aisHandler?._usCalc, them, _prefs, scale/scale2);
        return GestureDetector(
            // as the screen is pinched/stretched, so the range changes to match.
            onScaleUpdate: (s)=> scale2 = s.scale,

            // when the stretch.pinch ends, the scales is stored
            onScaleEnd: (s) {
              scale /= scale2;
              scale2=1;
            },

            onTapUp: (final TapUpDetails tud) {
              // convert the global offset to a canvas-local equivalent
              final Offset local = (context.findRenderObject() as RenderBox).globalToLocal(tud.globalPosition);

              // get any AIS object beneath the tap, this uses the path bounding boxes
              final List<Map<int,AIS>> details = aisPainter.getItemsAt(local);

              // nothing? - just return
              if (details == null || details.length == 0) {
                return;
              }

              // open up a page with the details
              Navigator.push(
                  context,
                  MaterialPageRoute(builder: (BuildContext context) => AISDetails(details))
              );
              },
            child: CustomPaint(
              size: constraints.biggest,
              painter: aisPainter
            )
        );
      }
    );
  }

  Widget buildList() {
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

class AISDetails extends StatelessWidget{
  final List<Map<int,AIS>> details;
  AISDetails(this.details);

  @override Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: Text('Details')),
        body: Text(details.toString())
    );
  }

}

class AISPainter extends CustomPainter {
  final PCS us;
  final Set<AISInfo> them;
  final AISSharedPreferences prefs;

  final Paint usPaint = Paint();
  final Paint themPaint = Paint();
  final Paint themAlertPaint = Paint();

  final double _range;
  
  AISPainter(this.us, this.them, this.prefs, this._range) {
    usPaint.style = PaintingStyle.stroke;

    themPaint.style = PaintingStyle.stroke;
    themPaint.color = Colors.green;

    themAlertPaint.style = PaintingStyle.stroke; // fill for dramatic effect?
    themAlertPaint.color = Colors.redAccent;
    themAlertPaint.strokeWidth = 2;
  }

  static final _boatSize = 30;  // means boat will fill 1/30th of the screen, seems about right visually
  static Path _boat(final Size canvasSize, double sog) {
    // double w = canvasSize.width/_boatSize;
    double h = canvasSize.height/_boatSize;
    double svec = (sog??0) == 0 ? 0 : h * (1+(sog/5));

    return Path()
        ..moveTo(0, 0)
        ..lineTo(h/2, -h)
        ..lineTo(-h/2, -h)
        ..lineTo(0, 0)
        ..lineTo(0, svec);
  }

  static Path _mark(final Size canvasSize) {
    double h2 = canvasSize.height/_boatSize/5;
    return Path()
        ..moveTo(h2,h2)
        ..lineTo(-h2,h2)
        ..lineTo(-h2,-h2)
        ..lineTo(h2,-h2)
        ..lineTo(h2,h2);
  }
  /// convert bearing degrees from north to cartesian angle degrees from X axis
  static double b2c(double b) {
    if (b <= 90) { return 90-b; }
    return 450-b;
  }

  // range indicates how wide our screen is in nautical miles
  // used to scale relative boat position
  static Matrix4 _transformation(PCS us, AISInfo them, double range, Size canvasSize, Matrix4 toScreen) {
    // need to check cog available, different return if not - blank?

    double w = canvasSize.width;
    double sx = w/range;

    double h = canvasSize.height;

    double dst = us.distanceTo(them.pcs);

    // make sure the target is within range before doing the expensive calcs:
    // this is only approximate, but still makes a huge difference to jank
    double xdim = range/2;
    double ydim = h/w*range*2/3;

    // maxRange is the square of the distance from us to the top corner of the screen.
    double maxRange = (xdim*xdim) + (ydim*ydim);
    if (maxRange < (dst*dst)) { return null; }

    // this should use hdg, not cog, ideally
    final double brg = rad(-us.bearingTo(them.pcs)+us.cog+90); // relative bearing in radians, cartesian
    final double xdst = dst*cos(brg);
    final double ydst = dst*sin(brg);

    return
      Matrix4.copy(toScreen)
      ..multiply(Matrix4.translationValues(xdst*sx, ydst*sx, 0))
      ..multiply(Matrix4.rotationZ(rad(us.cog-them.cog)));
  }

  // If there's a Type21 record, it's a mark, else a boat:
  static Path _getTargetPath(AISInfo them, Size canvasSize) {
    bool t21 = (them?._aisMap[21]) != null;
    Path target = t21
       ? _mark(canvasSize)
       : _boat(canvasSize, them.sog);
    return target;
  }

  Map<Rect, Map<int,AIS>> positions = Map();

  @override
  void paint(final Canvas canvas, final Size size) {
    positions.clear();

    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final Matrix4 toScreen = Matrix4.translationValues(size.width/2, 2*size.height/3, 0);
    toScreen.multiply(Matrix4.diagonal3Values(1, -1, 1)); // flip

    // 0,0 is top left corner, we want us to be at size.h/3, size.w/2

    // paint us:

    Path we = _boat(size, us?.sog??0).transform(toScreen.storage);

    Vector4 o = Vector4(0,0,0,1)..applyMatrix4(toScreen);

    label("US", canvas, o.x, o.y);

    canvas.drawPath(we, usPaint);

    // and each of them
    them.forEach((b)=>tgt(canvas, b, size, toScreen));
  }

  void label(String text, Canvas canvas, double x, double y) {
    final ParagraphBuilder pb = ParagraphBuilder(ParagraphStyle(maxLines: 1));
    ui.TextStyle style = ui.TextStyle(color:Colors.black);
    pb.pushStyle(style);
    pb.addText(text);
    final Paragraph pa =  pb.build();
    pa.layout(ParagraphConstraints(width: 150));
    canvas.drawParagraph(pa, Offset(x, y));
  }

  void tgt(Canvas c, AISInfo b, Size size, Matrix4 toScreen) {
    Matrix4 tr = _transformation(us, b, _range, size, toScreen);
    if (tr == null) {
      // out of range
      return;
    }

    Path ta = _getTargetPath(b, size).transform(tr.storage);

    Vector4 origin = tr.transform(Vector4(0, 0, 0, 1));
    double t = tcpa(us, b.pcs);
    if (t >=0 && t < .5 && cpa(us, b.pcs, t) < 1) {
      c.drawPath(ta, themAlertPaint);
    } else {
      c.drawPath(ta, themPaint);
    }
    String sl = b.ship??(b.mmsi.toString());
    // sl += ' '+us.bearingTo(b.pcs).toStringAsFixed(0);
    Rect bounds = ta.getBounds();
    label(sl, c, origin.x, origin.y);
    positions[bounds] = b.ais;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true; // oldDelegate != this;
  }

  List<Map<int,AIS>> getItemsAt(Offset globalPosition) {
    return positions
        .entries
        .where((e) => e.key.contains(globalPosition))
        .map((e) => e.value)
        .toList();
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

