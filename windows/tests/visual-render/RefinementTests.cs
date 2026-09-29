using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using IslandPrototype;

internal static class RefinementTests
{
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr h,out NativeRect rect);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect {public int Left,Top,Right,Bottom;}
    internal static async Task Run(IslandVisual surface,Window window,string directory)
    {
        var results=new List<object>();
        void Check(string name,bool pass,object? evidence=null){results.Add(new {check=name,pass,evidence});Console.WriteLine($"{(pass?"PASS":"FAIL")} {name}");}
        var medium=IslandTypography.Face(11,false,false);var semibold=IslandTypography.Face(13,true,false);
        bool mediumLoaded=medium.TryGetGlyphTypeface(out var m),semiboldLoaded=semibold.TryGetGlyphTypeface(out var s);
        Check("Both island text weights resolve from embedded fonts",mediumLoaded&&semiboldLoaded&&m.FontUri.Scheme=="pack"&&s.FontUri.Scheme=="pack"&&m.FontUri!=s.FontUri,new {medium=m?.FontUri.ToString(),semibold=s?.FontUri.ToString()});
        Check("Plan chips resolve a real bold face",IslandTypography.Face(9,true,true).TryGetGlyphTypeface(out var chip)&&chip.Weight==FontWeights.Bold,new {weight=chip?.Weight.ToString()});
        var start=new DateTime(DateTime.Today.Year,1,1);start=start.AddDays(-(int)start.DayOfWeek);int day=(DateTime.Today-start).Days;
        var target=new Point(16+day/7*13.95+5.8,38+81+day%7*13.95+5.8);
        surface.ActivateAt(target);await Task.Delay(45);double leaving=surface.DetailProgress;
        surface.ActivateAt(target);double resumed=surface.DetailProgress;
        Check("Reopening a closing detail preserves its displayed position",leaving is >0 and <1&&Math.Abs(leaving-resumed)<.02,new {leaving,resumed});
        await Task.Delay(150);double arriving=surface.DetailProgress;
        surface.ActivateAt(target);double reversed=surface.DetailProgress;
        Check("Closing an opening detail preserves its displayed position",arriving>leaving+.03&&arriving<1&&Math.Abs(arriving-reversed)<.02,new {arriving,reversed});
        await Task.Delay(250);
        Check("Detail collapse finishes in 200 ms and releases its clock",surface.DetailProgress==0&&!DependencyPropertyHelper.GetValueSource(surface,IslandVisual.DetailProgressProperty).IsAnimated);
        surface.Page=1;surface.BeginAnimation(IslandVisual.PagePositionProperty,new DoubleAnimation(2,1,TimeSpan.FromMilliseconds(360)));
        surface.BeginAnimation(IslandVisual.SwapOpacityProperty,new DoubleAnimation(0,1,TimeSpan.FromMilliseconds(220)));
        surface.BeginAnimation(IslandVisual.FeedbackOffsetProperty,new DoubleAnimation(-46,0,TimeSpan.FromMilliseconds(360)));
        surface.StartCounter(false);await Task.Delay(50);surface.ReduceMotion=true;
        Check("Enabling Reduce Motion settles active page, chart and value animations",surface.PagePosition==1&&surface.SwapOpacity==1&&surface.FeedbackOffset==0&&surface.CounterProgress==1&&new[]{IslandVisual.PagePositionProperty,IslandVisual.SwapOpacityProperty,IslandVisual.FeedbackOffsetProperty,IslandVisual.CounterProgressProperty}.All(p=>!DependencyPropertyHelper.GetValueSource(surface,p).IsAnimated));
        surface.ReduceMotion=false;
        surface.Height=226;window.Height=226;surface.ChartStyle=3;surface.CostStyle=0;
        foreach(double position in new[]{.35,.65}) {
            surface.PagePosition=position;surface.InvalidateVisual();await Task.Delay(250);
            GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var bounds);
            double dpi=VisualTreeHelper.GetDpi(surface).DpiScaleX;
            using var pixels=new System.Drawing.Bitmap((int)(800*dpi),(int)(226*dpi));
            using(var graphics=System.Drawing.Graphics.FromImage(pixels))graphics.CopyFromScreen(bounds.Left,bounds.Top,0,0,pixels.Size);
            pixels.Save(Path.Combine(directory,"mid-swipe-"+position+".png"),System.Drawing.Imaging.ImageFormat.Png);
            var meter=pixels.GetPixel((int)((598-800*position+45)*dpi),(int)(145*dpi));
            Check("Numeric meter remains attached to Usage at swipe position "+position,meter.B>180&&meter.R>120&&meter.B>meter.G,new {meter.R,meter.G,meter.B});
        }
        var original=ParityData.Providers.ToArray();
        string cache=Path.Combine(Path.GetTempPath(),"codex-island-visual-rates-"+Guid.NewGuid()+".json");
        File.WriteAllText(cache,JsonSerializer.Serialize(new {Rates=new Dictionary<string,double>{{"USD",1},{"CNY",7},{"EUR",.9},{"GBP",.8},{"JPY",150},{"KRW",1300},{"CAD",1.3},{"AUD",1.5},{"CHF",.9}},FetchedAt=DateTimeOffset.UtcNow,SourceDate=DateTimeOffset.UtcNow}));
        using var currency=new CurrencyStore(cache);surface.Currency=currency;surface.Page=1;surface.PagePosition=1;surface.CostStyle=0;surface.Height=226;window.Height=226;
        try {
            for(int i=0;i<original.Length;i++)ParityData.Providers[i]=original[i] with {Costs=original[i].Costs.Select(c=>c with {Dollars=1_234_567_890,Tokens=12_345_678_901}).ToArray()};
            foreach(string code in new[]{"USD","CHF","KRW"}) {
                currency.Selection=code;surface.InvalidateVisual();await Task.Delay(250);
                GetWindowRect(new System.Windows.Interop.WindowInteropHelper(window).Handle,out var rect);
                double dpi=VisualTreeHelper.GetDpi(surface).DpiScaleX;
                using var pixels=new System.Drawing.Bitmap((int)(800*dpi),(int)(226*dpi));
                using(var graphics=System.Drawing.Graphics.FromImage(pixels))graphics.CopyFromScreen(rect.Left,rect.Top,0,0,pixels.Size);
                pixels.Save(Path.Combine(directory,"large-"+code+".png"),System.Drawing.Imaging.ImageFormat.Png);
                int crossed=0;
                foreach(double edge in new[]{205.5,390,581.5,766})for(int x=(int)(edge*dpi);x<(int)((edge+10)*dpi);x++)for(int y=(int)(100*dpi);y<(int)(156*dpi);y++) {
                    var color=pixels.GetPixel(x,y);if(color.B>180&&color.R<210&&color.B-color.R>35)crossed++;
                }
                bool fullValueAvailable=surface.AccessibleDescription.Contains(currency.Format(1_234_567_890));
                Check(code+" large cost values stay inside their tiles",crossed==0&&fullValueAvailable,new {crossed,fullValueAvailable});
            }
        } finally{for(int i=0;i<original.Length;i++)ParityData.Providers[i]=original[i];surface.Currency=null;File.Delete(cache);}
        File.WriteAllText(Path.Combine(directory,"refinement-results.json"),JsonSerializer.Serialize(new {build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,checks=results},new JsonSerializerOptions {WriteIndented=true}));
        if(results.Any(x=>!JsonSerializer.SerializeToElement(x).GetProperty("pass").GetBoolean()))throw new InvalidOperationException("Visual refinement checks failed.");
    }
}
