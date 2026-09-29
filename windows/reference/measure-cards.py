from pathlib import Path
import subprocess
root=Path(__file__).resolve().parents[2]
art=root/'windows/artifacts/card-layout'
art.mkdir(exist_ok=True)
s=(root/'Sources/Sharing/WeeklyUsageCard.swift').read_text()
replacements={
'            heading\n':'            heading.cardMeasure("heading")\n',
'            WeeklyValueFlow(snapshot: snapshot, theme: theme, metric: metric)':'            WeeklyValueFlow(snapshot: snapshot, theme: theme, metric: metric).cardMeasure("flow")',
'            providerLegend\n':'            providerLegend.cardMeasure("legend")\n',
'            footer\n':'            footer.cardMeasure("footer")\n',
'            .font(.system(size: 12, weight: .medium))\n            .foregroundStyle(theme.secondary)':'            .font(.system(size: 12, weight: .medium))\n            .cardMeasure("date")\n            .foregroundStyle(theme.secondary)',
'                    .frame(maxWidth: .infinity, alignment: .leading)':'                    .frame(maxWidth: .infinity, alignment: .leading).cardMeasure("headline")',
'                moneyHeadline\n':'                moneyHeadline.cardMeasure("money")\n',
'                .font(.system(size: compact ? 94 : 112, weight: .regular, design: .rounded))':'                .font(.system(size: compact ? 94 : 112, weight: .regular, design: .rounded)).cardMeasure("tokens")',
'            .font(.system(size: 13, weight: .medium))':'            .font(.system(size: 13, weight: .medium)).cardMeasure("activity")',
'            Canvas { context, size in draw(in: &context, size: size) }':'            Canvas { context, size in draw(in: &context, size: size) }.cardMeasure("canvas")',
'                Text("API-rate estimate, not a bill.")':'                Text("API-rate estimate, not a bill.")',
'                    .font(.system(size: 10, weight: .medium))':'                    .font(.system(size: 10, weight: .medium)).cardMeasure("disclaimer")',
}
for old,new in replacements.items():
 assert old in s,old
 s=s.replace(old,new)
s+='''\n@MainActor enum CardMeasurements { static var frames:[String:CGRect]=[:] }\nextension View { func cardMeasure(_ name:String)->some View { background(GeometryReader { proxy in Color.clear.onAppear { CardMeasurements.frames[name]=proxy.frame(in:.global) }.onChange(of:proxy.frame(in:.global)) { CardMeasurements.frames[name]=$0 } }) } }\n'''
(art/'MeasuredWeeklyUsageCard.swift').write_text(s)
main=(root/'windows/reference/RenderMacReference.swift').read_text()
a=main.index('        let notch = ')
b=main.index('        let cardBuckets = ')
main=main[:a]+main[b:]
main=main.replace('                try save(WeeklyUsageCard','                CardMeasurements.frames=[:]\n                try save(WeeklyUsageCard')
main=main.replace('name: "card-\\(format.rawValue)-\\(metric.rawValue)", to: destination)','name: "card-\\(format.rawValue)-\\(metric.rawValue)", to: destination)\n                let measured=CardMeasurements.frames.mapValues { ["x":$0.minX,"y":$0.minY,"width":$0.width,"height":$0.height] }\n                try JSONSerialization.data(withJSONObject:measured,options:[.prettyPrinted,.sortedKeys]).write(to:destination.appendingPathComponent("card-\\(format.rawValue)-\\(metric.rawValue).json"))')
a=main.index('        try save(WeeklyCardStudio')
b=main.index('    static func save<')
main=main[:a]+'    }\n\n'+main[b:]
(art/'MeasureCards.swift').write_text(main)
sources=sorted(root.glob('Sources/**/*.swift'))
sources=[str(art/'MeasuredWeeklyUsageCard.swift') if p.name=='WeeklyUsageCard.swift' else str(p) for p in sources if p.name!='App.swift']
cmd=['swiftc','-Onone','-target','arm64-apple-macos13.0','-parse-as-library','-F',str(root/'Vendor/Sparkle'),'-framework','SwiftUI','-framework','AppKit','-framework','ServiceManagement','-framework','Sparkle','-Xlinker','-rpath','-Xlinker',str(root/'Vendor/Sparkle'),'-o',str(art/'MeasureCards'),*sources,str(art/'MeasureCards.swift')]
subprocess.run(cmd,check=True)
import os
subprocess.run([str(art/'MeasureCards'),str(art)],env={**os.environ,'CODEXISLAND_DEMO':'1'},check=True)
