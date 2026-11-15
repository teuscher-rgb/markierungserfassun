import SwiftUI
import CoreLocation
import UIKit
import MapKit

struct Markierung: Identifiable, Codable {
    var id = UUID()
    var datum = Date()
    var gemeinde = ""
    var strasse = ""
    var typ = "Fussgängerstreifen"
    var laenge = 0.0
    var breite = 0.0
    var anzahl = 1
    var zustand = "Stark abgenutzt"
    var prioritaet = "Mittel"
    var bemerkung = ""
    var latitude: Double?
    var longitude: Double?
    var fotoDatei: String?
    var linien: [[Kartenpunkt]] = []
    // Polygons for individual stripes, arrows or painted islands.
    var einzelFlaechen: [[Kartenpunkt]] = []
    var markierungsAnteil = 1.0 // dashed lines: painted fraction 0...1
    var flaeche: Double {
        let polygonFlaeche = einzelFlaechen.reduce(0) { $0 + $1.flaecheQuadratmeter }
        let linienFlaeche = linien.isEmpty ? (einzelFlaechen.isEmpty ? laenge * breite * Double(anzahl) * markierungsAnteil : 0) : laenge * breite * markierungsAnteil
        return polygonFlaeche + linienFlaeche
    }
}

@MainActor final class Daten: ObservableObject {
    @Published var eintraege: [Markierung] = [] { didSet { speichern() } }
    private var ordner: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    init() { if let data = try? Data(contentsOf: ordner.appendingPathComponent("markierungen.json")), let liste = try? JSONDecoder().decode([Markierung].self, from: data) { eintraege = liste } }
    func speichern() { if let data = try? JSONEncoder().encode(eintraege) { try? data.write(to: ordner.appendingPathComponent("markierungen.json"), options: .atomic) } }
    func fotoSpeichern(_ bild: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let data = bild.jpegData(compressionQuality: 0.78) else { return nil }
        do { try data.write(to: ordner.appendingPathComponent(name)); return name } catch { return nil }
    }
    func bild(_ name: String?) -> UIImage? { guard let name else { return nil }; return UIImage(contentsOfFile: ordner.appendingPathComponent(name).path) }
    private func csvFeld(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
    func csv() -> URL? {
        var zeilen = ["Datum;Gemeinde;Strasse;Typ;Laenge_m;Breite_m;Anzahl;Flaeche_m2;Zustand;Prioritaet;Breitengrad;Laengengrad;Bemerkung;Linien_GeoJSON;Flaechen_GeoJSON;Markierungsanteil"]
        let formatter = ISO8601DateFormatter()
        for m in eintraege {
            let felder = [formatter.string(from: m.datum),m.gemeinde,m.strasse,m.typ,String(m.laenge),String(m.breite),String(m.anzahl),String(m.flaeche),m.zustand,m.prioritaet,m.latitude.map(String.init) ?? "",m.longitude.map(String.init) ?? "",m.bemerkung, m.linienGeoJSON, m.flaechenGeoJSON, String(m.markierungsAnteil)]
            zeilen.append(felder.map(csvFeld).joined(separator: ";"))
        }
        let url = ordner.appendingPathComponent("Markierungen_Excel.csv")
        do { try ("\u{FEFF}" + zeilen.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
    func pdf() -> URL? {
        let url = ordner.appendingPathComponent("Markierungen_Bericht.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        do {
            try renderer.writePDF(to: url) { context in
                for (index,m) in eintraege.enumerated() {
                    context.beginPage()
                    let title = "Strassenmarkierungen – Erneuerung"
                    (title as NSString).draw(at: CGPoint(x: 40,y: 35), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                    let datum = DateFormatter(); datum.dateStyle = .medium
                    let lines = ["Eintrag \(index + 1) / \(eintraege.count)","Datum: \(datum.string(from: m.datum))","Gemeinde: \(m.gemeinde)","Strasse: \(m.strasse)","Typ: \(m.typ)","Länge: \(m.laenge) m   Breite: \(m.breite) m   Anzahl: \(m.anzahl)",String(format: "Fläche: %.2f m²", m.flaeche),"Zustand: \(m.zustand)   Priorität: \(m.prioritaet)","GPS: \(m.latitude.map(String.init) ?? "–"), \(m.longitude.map(String.init) ?? "–")","Bemerkung: \(m.bemerkung)", "Gezeichnete Linien: \(m.linien.count) · Einzelflächen: \(m.einzelFlaechen.count)"]
                    var y: CGFloat = 90
                    for line in lines { (line as NSString).draw(in: CGRect(x: 40,y: y,width: 515,height: 48), withAttributes: [.font: UIFont.systemFont(ofSize: 13)]); y += 37 }
                    if let bild = bild(m.fotoDatei) {
                        let maxSize = CGSize(width: 510,height: 330)
                        let scale = min(maxSize.width/bild.size.width,maxSize.height/bild.size.height)
                        bild.draw(in: CGRect(x: 40,y: y+10,width: bild.size.width*scale,height: bild.size.height*scale))
                    }
                }
                if eintraege.isEmpty { context.beginPage(); ("Keine Einträge vorhanden" as NSString).draw(at: CGPoint(x: 40,y: 40), withAttributes: [.font: UIFont.systemFont(ofSize: 16)]) }
            }
            return url
        } catch { return nil }
    }
}

final class Standort: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var koordinaten: CLLocationCoordinate2D?
    @Published var meldung = "Standort noch nicht erfasst"
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func erfassen() { manager.requestWhenInUseAuthorization(); manager.requestLocation() }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { koordinaten = locations.last?.coordinate; meldung = koordinaten == nil ? "Kein GPS-Signal" : "GPS-Standort erfasst" }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { meldung = "GPS: \(error.localizedDescription)" }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() } }
}

struct Kamera: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onBild: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: Kamera
        init(_ parent: Kamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) { if let bild = info[.originalImage] as? UIImage { parent.onBild(bild) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}


struct Kartenpunkt: Codable, Hashable {
    var lat: Double
    var lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
extension Array where Element == Kartenpunkt {
    var flaecheQuadratmeter: Double {
        guard count >= 3 else { return 0 }
        // Project to local metric coordinates to avoid degree-based area calculations.
        let origin = MKMapPoint(first!.coordinate)
        let scale = MKMetersPerMapPointAtLatitude(first!.lat)
        let pts = map { p -> (Double, Double) in
            let mp = MKMapPoint(p.coordinate)
            return ((mp.x - origin.x) * scale, (mp.y - origin.y) * scale)
        }
        var twiceArea = 0.0
        for i in pts.indices {
            let j = (i + 1) % pts.count
            twiceArea += pts[i].0 * pts[j].1 - pts[j].0 * pts[i].1
        }
        return abs(twiceArea) / 2
    }
}
extension Markierung {
    var flaechenGeoJSON: String {
        let rings = einzelFlaechen.map { polygon -> [[[Double]]] in
            let coords = polygon.map { [$0.lon, $0.lat] }
            return [coords + (coords.first.map { [$0] } ?? [])]
        }
        let obj: [String: Any] = ["type": "MultiPolygon", "coordinates": rings]
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }
}
extension Markierung {
    var linienGeoJSON: String {
        let coords = linien.map { line in line.map { [$0.lon, $0.lat] } }
        let obj: [String: Any] = ["type":"MultiLineString", "coordinates":coords]
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let str = String(data: d, encoding: .utf8) else { return "" }
        return str
    }
}

// Pencil-only input, while finger gestures keep map navigation available.
final class ZeichenFlaeche: UIView {
    var onFinish: (([CGPoint]) -> Void)?
    private var points: [CGPoint] = []
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false; isMultipleTouchEnabled = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        event?.allTouches?.contains(where: { $0.type == .pencil }) ?? false
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, t.type == .pencil else { return }
        points = [t.location(in: self)]
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, t.type == .pencil else { return }
        points.append(t.location(in: self)); setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, t.type == .pencil else { return }
        points.append(t.location(in: self)); if points.count > 1 { onFinish?(points) }
        points = []; setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard points.count > 1 else { return }
        let path = UIBezierPath(); path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        UIColor.systemRed.setStroke(); path.lineWidth = 4; path.lineCapStyle = .round; path.stroke()
    }
}


// GIS Solothurn WMS: tiles are cached locally after viewing. Only cached tiles
// are available without a network connection; this is NOT a full offline package.
final class SolothurnWMS: MKTileOverlay {
    static let source = "Kanton Solothurn, Amt für Geoinformation (WMS)"
    private let fm = FileManager.default
    private let cache: URL
    override init(urlTemplate: String? = nil) {
        cache = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("solothurn-wms-2017", isDirectory: true)
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        canReplaceMapContent = false
        minimumZ = 8
        maximumZ = 20
        try? fm.createDirectory(at: cache, withIntermediateDirectories: true)
    }
    private func latitude(_ y: Double, zoom z: Int) -> Double {
        atan(sinh(.pi * (1 - 2 * y / pow(2, Double(z))))) * 180 / .pi
    }
    private func tileURL(_ p: MKTileOverlayPath) -> URL? {
        let n = pow(2, Double(p.z))
        let west = Double(p.x) / n * 360 - 180
        let east = Double(p.x + 1) / n * 360 - 180
        let north = latitude(Double(p.y), zoom: p.z)
        let south = latitude(Double(p.y + 1), zoom: p.z)
        var c = URLComponents(string: "https://geo.so.ch/api/wms")
        c?.queryItems = [
            URLQueryItem(name: "SERVICE", value: "WMS"),
            URLQueryItem(name: "VERSION", value: "1.1.1"),
            URLQueryItem(name: "REQUEST", value: "GetMap"),
            URLQueryItem(name: "LAYERS", value: "ch.so.agi.orthofoto_2017_rgb"),
            URLQueryItem(name: "STYLES", value: ""),
            URLQueryItem(name: "FORMAT", value: "image/jpeg"),
            URLQueryItem(name: "SRS", value: "EPSG:4326"),
            URLQueryItem(name: "WIDTH", value: "256"),
            URLQueryItem(name: "HEIGHT", value: "256"),
            URLQueryItem(name: "BBOX", value: "\(west),\(south),\(east),\(north)")
        ]
        return c?.url
    }
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let file = cache.appendingPathComponent("\(path.z)_\(path.x)_\(path.y).jpg")
        if let data = try? Data(contentsOf: file) { result(data, nil); return }
        guard let url = tileURL(path) else {
            result(nil, NSError(domain: "SolothurnWMS", code: 1)); return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data, let http = response as? HTTPURLResponse,
                  http.statusCode == 200, UIImage(data: data) != nil else {
                result(nil, error ?? NSError(domain: "SolothurnWMS", code: 2)); return
            }
            try? data.write(to: file, options: .atomic)
            result(data, nil)
        }.resume()
    }
}

struct ZeichenKarte: UIViewRepresentable {
    var gisAktiv: Bool = false
    @Binding var linien: [[Kartenpunkt]]
    @Binding var einzelFlaechen: [[Kartenpunkt]]
    var modus: ZeichenModus
    var start: CLLocationCoordinate2D?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        if gisAktiv { map.addOverlay(SolothurnWMS(), level: .aboveLabels) }
        map.delegate = context.coordinator
        map.setRegion(MKCoordinateRegion(center: start ?? CLLocationCoordinate2D(latitude: 47.207, longitude: 7.537), span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)), animated: false)
        let zeichnen = ZeichenFlaeche(frame: map.bounds)
        zeichnen.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        zeichnen.onFinish = { [weak map] points in
            guard let map else { return }
            let line = points.map { p -> Kartenpunkt in
                let c = map.convert(p, toCoordinateFrom: zeichnen)
                return Kartenpunkt(lat: c.latitude, lon: c.longitude)
            }
            if context.coordinator.parent.modus == .strecke {
                context.coordinator.parent.linien.append(line)
            } else if line.count >= 3 {
                context.coordinator.parent.einzelFlaechen.append(line)
            }
        }
        map.addSubview(zeichnen)
        return map
    }
    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let vorhandeneGIS = map.overlays.compactMap { $0 as? SolothurnWMS }
        if gisAktiv && vorhandeneGIS.isEmpty { map.addOverlay(SolothurnWMS(), level: .aboveLabels) }
        if !gisAktiv { map.removeOverlays(vorhandeneGIS) }
        map.removeOverlays(map.overlays.filter { !($0 is SolothurnWMS) })
        for polygon in einzelFlaechen where polygon.count > 2 {
            let coords = polygon.map(\.coordinate)
            map.addOverlay(MKPolygon(coordinates: coords, count: coords.count))
        }
        for line in linien where line.count > 1 {
            let coords = line.map(\.coordinate)
            map.addOverlay(MKPolyline(coordinates: coords, count: coords.count))
        }
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ZeichenKarte
        init(_ parent: ZeichenKarte) { self.parent = parent }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let gis = overlay as? SolothurnWMS { return MKTileOverlayRenderer(tileOverlay: gis) }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .systemOrange
                renderer.fillColor = UIColor.systemOrange.withAlphaComponent(0.3)
                renderer.lineWidth = 3
                return renderer
            }
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.strokeColor = .systemRed; renderer.lineWidth = 4
            return renderer
        }
    }
}

enum ZeichenModus: String, CaseIterable, Identifiable {
    case strecke = "Strecke"
    case einzeln = "Einzelflächen"
    var id: String { rawValue }
}

struct KartenEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var linien: [[Kartenpunkt]]
    @Binding var laenge: Double
    @Binding var einzelFlaechen: [[Kartenpunkt]]
    @State private var modus: ZeichenModus = .strecke
    @State private var gisAktiv = false
    var start: CLLocationCoordinate2D?
    var meter: Double {
        linien.reduce(0) { total, line in
            total + zip(line, line.dropFirst()).reduce(0) { sum, pair in
                sum + CLLocation(latitude: pair.0.lat, longitude: pair.0.lon).distance(from: CLLocation(latitude: pair.1.lat, longitude: pair.1.lon))
            }
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Zeichenmodus", selection: $modus) {
                    ForEach(ZeichenModus.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).padding()
                Toggle("GIS Solothurn Orthofoto (2017)", isOn: $gisAktiv)
                    .padding(.horizontal)
                ZeichenKarte(gisAktiv: gisAktiv, linien: $linien, einzelFlaechen: $einzelFlaechen, modus: modus, start: start)
                HStack {
                    VStack(alignment: .leading) {
                        Text(modus == .strecke ? "Pencil: Strecke zeichnen" : "Pencil: Umriss einer Markierung zeichnen").font(.headline)
                        Text("Finger: Karte bewegen · \(linien.count) Strecken · \(einzelFlaechen.count) Flächen").font(.caption)
                        if gisAktiv { Text("© Kanton Solothurn / AGI · Bereits geladene GIS-Kacheln sind zwischengespeichert").font(.caption2) }
                        Text("Strecken: \(meter, specifier: "%.1f") m · Einzelflächen: \(einzelFlaechen.reduce(0) { $0 + $1.flaecheQuadratmeter }, specifier: "%.2f") m²").font(.caption)
                    }
                    Spacer()
                    Button("Rückgängig") {
                        if modus == .strecke { if !linien.isEmpty { linien.removeLast() } }
                        else { if !einzelFlaechen.isEmpty { einzelFlaechen.removeLast() } }
                    }.disabled(modus == .strecke ? linien.isEmpty : einzelFlaechen.isEmpty)
                }.padding()
            }
            .navigationTitle("Strassenabschnitt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schliessen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { if !linien.isEmpty { laenge = meter }; dismiss() } }
            }
        }
    }
}

struct ExportDatei: Identifiable { let id = UUID(); let url: URL }
struct Teilen: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct Erfassen: View {
    @EnvironmentObject var daten: Daten
    @Environment(\.dismiss) var dismiss
    @StateObject private var standort = Standort()
    @State private var m = Markierung()
    @State private var bild: UIImage?
    @State private var kamera = false
    @State private var karte = false
    let typen = ["Fussgängerstreifen","Mittellinie","Randlinie","Leitlinie","Stopplinie","Pfeil / Symbol","Parkfeld","Andere"]
    var body: some View {
        NavigationStack {
            Form {
                Section("Ort") {
                    TextField("Gemeinde", text: $m.gemeinde)
                    TextField("Strasse / Abschnitt", text: $m.strasse)
                    Button("GPS-Standort erfassen") { standort.erfassen() }
                    Text(standort.meldung).font(.caption)
                }
                Section("Satellitenkarte / Apple Pencil") {
                    Button("Strassenabschnitt auf Karte einzeichnen") { karte = true }
                    Text("\(m.linien.count) Strecken · \(m.einzelFlaechen.count) Einzelflächen").font(.caption)
                    Text("Streckenfläche und einzeln gezeichnete Flächen werden addiert; Doppelzeichnungen vermeiden.").font(.caption)
                }
                Section("Markierung") {
                    Picker("Typ", selection: $m.typ) { ForEach(typen,id: \.self) { Text($0) } }
                    HStack { Text("Länge (m)"); Spacer(); TextField("0", value: $m.laenge, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Breite (m)"); Spacer(); TextField("0", value: $m.breite, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    Stepper("Anzahl: \(m.anzahl)", value: $m.anzahl, in: 1...10000)
                    HStack {
                            Text("Markierter Streckenanteil")
                            Slider(value: $m.markierungsAnteil, in: 0...1, step: 0.05)
                            Text("\(Int(m.markierungsAnteil * 100)) %")
                        }
                    Text("Fläche: \(m.flaeche, specifier: "%.2f") m²").bold()
                }
                Section("Erneuerung") {
                    Picker("Zustand", selection: $m.zustand) { ForEach(["Leicht abgenutzt","Stark abgenutzt","Nicht mehr sichtbar"],id: \.self) { Text($0) } }
                    Picker("Priorität", selection: $m.prioritaet) { ForEach(["Niedrig","Mittel","Hoch"],id: \.self) { Text($0) } }
                    TextField("Bemerkung", text: $m.bemerkung, axis: .vertical)
                }
                Section("Foto") {
                    Button("Foto aufnehmen / auswählen") { kamera = true }
                    if let bild { Image(uiImage: bild).resizable().scaledToFit().frame(maxHeight: 250) }
                }
            }
            .navigationTitle("Neue Markierung")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Speichern") {
                m.latitude = standort.koordinaten?.latitude
                m.longitude = standort.koordinaten?.longitude
                if let bild { m.fotoDatei = daten.fotoSpeichern(bild) }
                daten.eintraege.append(m); dismiss()
            }.disabled(m.strasse.trimmingCharacters(in: .whitespaces).isEmpty || m.laenge < 0 || m.breite < 0) } }
            .sheet(isPresented: $kamera) { Kamera { bild = $0 } }
            .sheet(isPresented: $karte) { KartenEditor(linien: $m.linien, laenge: $m.laenge, einzelFlaechen: $m.einzelFlaechen, start: standort.koordinaten) }
        }
    }
}

struct Hauptansicht: View {
    @StateObject private var daten = Daten()
    @State private var neu = false
    @State private var export: ExportDatei?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("\(daten.eintraege.count) Markierungen · \(daten.eintraege.reduce(0) { $0 + $1.flaeche }, specifier: "%.2f") m² gesamt").font(.headline) }
                ForEach(daten.eintraege) { m in
                    HStack(spacing: 12) {
                        if let bild = daten.bild(m.fotoDatei) { Image(uiImage: bild).resizable().scaledToFill().frame(width: 70,height: 70).clipped().cornerRadius(8) }
                        VStack(alignment: .leading,spacing: 5) { Text(m.strasse).font(.headline); Text("\(m.gemeinde) · \(m.typ)").font(.subheadline); Text("\(m.flaeche, specifier: "%.2f") m² · \(m.prioritaet)").font(.caption) }
                    }
                }.onDelete { daten.eintraege.remove(atOffsets: $0) }
            }
            .navigationTitle("Markierungserfassung")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Menu("Export") { Button("PDF-Bericht") { if let url = daten.pdf() { export = ExportDatei(url: url) } }; Button("Excel (CSV)") { if let url = daten.csv() { export = ExportDatei(url: url) } } } }
                ToolbarItem(placement: .topBarTrailing) { Button { neu = true } label: { Label("Erfassen", systemImage: "plus") } }
            }
            .sheet(isPresented: $neu) { Erfassen().environmentObject(daten) }
            .sheet(item: $export) { Teilen(url: $0.url) }
        }
    }
}

@main struct MarkierungserfassungApp: App {
    var body: some Scene { WindowGroup { Hauptansicht() } }
}
