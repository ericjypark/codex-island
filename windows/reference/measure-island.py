from pathlib import Path
import json, os, re, shutil, subprocess
root=Path(__file__).resolve().parents[2]
art=root/'windows/artifacts/island-layout'
art.mkdir(parents=True,exist_ok=True)
app=art/'IslandMeasure.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copytree(root/'windows/artifacts/MacReference.app/Contents/Resources',app/'Contents/Resources',dirs_exist_ok=True)
(app/'Contents/Info.plist').write_text('''<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.codexisland.IslandLayoutReference</string><key>CFBundleExecutable</key><string>IslandMeasure</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/></dict></plist>''')
sources=[]
for path in sorted(root.glob('Sources/**/*.swift')):
    if path.name=='App.swift': continue
    source=path.read_text()
    if path.name=='UpdaterController.swift': source=source.replace('startingUpdater: true','startingUpdater: false')
    if path.name=='OverviewView.swift': source=source.replace('@State private var selectedDate: Date?','@State private var selectedDate: Date? = ProcessInfo.processInfo.environment["WINDOWS_REFERENCE_DAY"].flatMap { ISO8601DateFormatter().date(from: $0) }')
    if path.name=='CodexResetStatus.swift': source=source.replace('@State private var showPopover = false','@State private var showPopover = ProcessInfo.processInfo.environment["WINDOWS_REFERENCE_RESETS"] == "1"')
    if ('/Views/' in str(path) and '/Settings/' not in str(path)) or path.name=='WeeklyCardWindowController.swift':
        def mark(match):
            line=source[:match.start()].count('\n')+1
            name=f'{path.stem}:{line}:{match.group(1)}'
            return match.group(0)+f'.islandMeasure("{name}")'
        source=re.sub(r'\.font\(Typography\.(\w+)\)(?:\s*\.tracking\([^\n]*?\))?',mark,source)
    if source!=path.read_text():
        copy=art/path.name;copy.write_text(source);sources.append(str(copy))
    else: sources.append(str(path))
helper=art/'MeasureLayout.swift'
helper.write_text('''import SwiftUI
@MainActor enum IslandMeasurements {
    static var offsets: [String: Double] = [:]
    static var frames: [String: [String: Double]] = [:]
}
struct IslandMeasureLayout: Layout {
    let name: String
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { subviews[0].sizeThatFits(proposal) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        MainActor.assumeIsolated { IslandMeasurements.offsets[name] = subviews[0].dimensions(in: proposal)[.firstTextBaseline] }
        subviews[0].place(at: bounds.origin, proposal: proposal)
    }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { subviews[0].dimensions(in: proposal)[guide] }
}
extension View {
    func islandMeasure(_ name: String) -> some View {
        IslandMeasureLayout(name:name) { self }.modifier(IslandFrameRecorder(name:name))
    }
}
private struct IslandFrameRecorder: ViewModifier {
    let name: String
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Color.clear.onAppear { record(frame, name) }.onChange(of: frame) { record($0, name) }
        })
    }
    private func record(_ frame: CGRect, _ name: String) {
        IslandMeasurements.frames[name + "@" + id.uuidString] = ["x": frame.minX,"y":frame.minY,"width":frame.width,"height":frame.height,"baseline":frame.minY+(IslandMeasurements.offsets[name] ?? 0)]
    }
}
''')
main=(root/'windows/reference/RenderMacReference.swift').read_text()
a=main.index('        for tab in [')
b=main.index('    static func save<')
main=main[:a]+'''        ScreenPref.shared.screen = .usage
        StylePref.shared.style = .bar
        ProviderVisibilityStore.shared.set(nil, at: 1)
        try save(ExpandedView(model: model).frame(width:800).background(.black), name:"single-models", to:destination)
        setenv("WINDOWS_REFERENCE_RESETS","1",1)
        try save(ExpandedView(model: model).frame(width:800).background(.black), name:"reset-popover", to:destination)
    }

'''+main[b:]
main=main.replace('        let host = NSHostingView','        IslandMeasurements.frames = [:]\n        let host = NSHostingView')
main=main.replace('        window.close()','        try JSONSerialization.data(withJSONObject: IslandMeasurements.frames, options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent(name+".json"))\n        window.close()')
mainpath=art/'MeasureMain.swift';mainpath.write_text(main)
cmd=['swiftc','-Onone','-target','arm64-apple-macos13.0','-parse-as-library','-F',str(root/'Vendor/Sparkle'),'-framework','SwiftUI','-framework','AppKit','-framework','ServiceManagement','-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(root/'Vendor/Sparkle'),'-o',str(app/'Contents/MacOS/IslandMeasure'),*sources,str(helper),str(mainpath)]
subprocess.run(cmd,check=True)
subprocess.run([str(app/'Contents/MacOS/IslandMeasure'),str(art)],env={**os.environ,'CODEXISLAND_DEMO':'1'},check=True)
for path in sorted(art.glob('*.json')):
    data=json.loads(path.read_text());print(path.name,len(data),'measured text frames')
