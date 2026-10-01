using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class Program
{
    [STAThread] private static void Main(string[] args)
    {
        _=new Application();string output=args[0];Directory.CreateDirectory(output);
        var checks=new List<object>();
        void Check(string name,bool pass) {checks.Add(new {check=name,pass});Console.WriteLine((pass?"PASS: ":"FAIL: ")+name);if(!pass)throw new Exception(name);}
        foreach(double size in new[]{12.0,14,36,112}) {
            var face=CardTypography.Face(size,size==14,size==112);
            Check("Embedded card font resolves at "+size,face.TryGetGlyphTypeface(out var glyph)&&glyph.FontUri.ToString().Contains("CodexIslandPrototype;component/Assets/Fonts/",StringComparison.OrdinalIgnoreCase));
        }
        var all=ParityData.Providers.Select(p=>p.Id).ToHashSet();
        var snapshot=new UsageCardSnapshot(CardPeriod.LastSevenDays,all,ParityData.FixtureDate);
        void Save(string name,UsageCardSnapshot data,CardFormat format,CardMetric metric,string signature="") {
            var visual=new UsageCardVisual(data) {Format=format,Metric=metric,Signature=signature};
            var bitmap=visual.Bitmap();var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using(var stream=File.Create(Path.Combine(output,name+".png")))encoder.Save(stream);
            Check(name+": full-resolution export",bitmap.PixelWidth==1080&&bitmap.PixelHeight==(format==CardFormat.Feed?1350:format==CardFormat.Square?1080:1920));
            var pixels=new byte[bitmap.PixelWidth*bitmap.PixelHeight*4];bitmap.CopyPixels(pixels,bitmap.PixelWidth*4,0);
            int bottom=(int)((visual.CardHeight-(format==CardFormat.Story?88:32))*2);
            int outside=0;for(int y=0;y<bitmap.PixelHeight;y++)for(int x=0;x<bitmap.PixelWidth;x++) {
                int i=(y*bitmap.PixelWidth+x)*4;
                if((x<64||x>=1016||y>bottom+3)&&(pixels[i]!=pixels[0]||pixels[i+1]!=pixels[1]||pixels[i+2]!=pixels[2]))outside++;
            }
            Check(name+": content stays within card margins",outside==0);
        }
        foreach(var format in Enum.GetValues<CardFormat>())foreach(var metric in Enum.GetValues<CardMetric>())
            Save("win-card-"+format.ToString().ToLowerInvariant()+"-"+(metric==CardMetric.ApiValue?"apiValue":"tokens"),snapshot,format,metric);
        var day=ParityData.FixtureDate;
        UsageCardSnapshot Data(long tokens,double? dollars,bool partial=false)=>new(CardPeriod.LastSevenDays,new(){"codex"},day,
            [new DemoDay(day,new(){{"codex",tokens}},new(){{"codex",tokens}},dollars is {} amount?new(){{"codex",amount}}:new(),partial?new(){{"codex",tokens/2}}:null)],false);
        Save("card-white-subcent",Data(1000,.004),CardFormat.Square,CardMetric.ApiValue);
        Save("card-white-tokens",Data(42000,.15),CardFormat.Feed,CardMetric.Tokens);
        Save("card-black-tokens",Data(420000000,1000),CardFormat.Story,CardMetric.Tokens);
        Save("card-blue-large-value",Data(4200000000,1234567890.12),CardFormat.Square,CardMetric.ApiValue);
        Save("card-partial-value",Data(150000,.123,true),CardFormat.Feed,CardMetric.ApiValue,"@developer • 사용자");
        Save("card-unpriced",Data(150000,null),CardFormat.Square,CardMetric.ApiValue);
        Save("card-long-signature",snapshot,CardFormat.Feed,CardMetric.Tokens,new string('W',32));
        File.WriteAllText(Path.Combine(output,"card-render-results.json"),JsonSerializer.Serialize(new {build=typeof(UsageCardVisual).Module.ModuleVersionId,checks},new JsonSerializerOptions {WriteIndented=true}));
    }
}
