import 'package:rideatlas/services/kml_parser.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses nested Folder with MultiGeometry LineString', () {
    const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Europe tour</name>
    <Folder>
      <Placemark>
        <name>Day 1</name>
        <MultiGeometry>
          <LineString>
            <coordinates>29.0,41.0,100 29.1,41.1,110</coordinates>
          </LineString>
        </MultiGeometry>
      </Placemark>
      <Placemark>
        <MultiGeometry>
          <LineString>
            <coordinates>29.2,41.2,0 29.3,41.3,0</coordinates>
          </LineString>
        </MultiGeometry>
      </Placemark>
    </Folder>
  </Document>
</kml>
''';

    final parsed = parseKmlXml(kml);
    expect(parsed.suggestedName, 'Europe tour');
    expect(parsed.points.length, 4);
    expect(parsed.points.first.latLng.latitude, closeTo(41.0, 0.001));
    expect(parsed.points.last.latLng.latitude, closeTo(41.3, 0.001));
  });

  test('parses gx Track with interleaved when/coord', () {
    const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <Placemark>
      <gx:Track>
        <when>2024-06-01T10:00:00Z</when>
        <gx:coord>29.0 41.0 50</gx:coord>
        <when>2024-06-01T10:05:00Z</when>
        <gx:coord>29.1 41.1 55</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>
''';

    final parsed = parseKmlXml(kml);
    expect(parsed.points.length, 2);
    expect(parsed.points.first.time, isNotNull);
    expect(parsed.points.first.elevation, closeTo(50, 0.1));
  });

  test('LineString still parsed when gx Track exists elsewhere', () {
    const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
     xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document>
    <Placemark>
      <LineString><coordinates>28.0,40.0,0 28.1,40.1,0</coordinates></LineString>
    </Placemark>
    <Placemark>
      <gx:Track>
        <gx:coord>28.2 40.2 0</gx:coord>
      </gx:Track>
    </Placemark>
  </Document>
</kml>
''';

    final parsed = parseKmlXml(kml);
    expect(parsed.points.length, 3);
  });

  test('Point placemark inside nested folder becomes waypoint', () {
    const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Folder>
      <Placemark>
        <name>Camp</name>
        <Point><coordinates>29.5,41.5,0</coordinates></Point>
      </Placemark>
    </Folder>
    <Placemark>
      <LineString><coordinates>29.0,41.0,0 29.1,41.1,0</coordinates></LineString>
    </Placemark>
  </Document>
</kml>
''';

    final parsed = parseKmlXml(kml);
    expect(parsed.points.length, 2);
    expect(parsed.waypoints.length, 1);
    expect(parsed.waypoints.first.name, 'Camp');
  });
}
