using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using IslandPrototype;

internal static class PillMotionTests
{
    internal static async Task Run(IslandVisual surface,Border host,Window window,string output)
    {
        var checks=new List<object>();int failures=0;
        void Check(string name,bool pass){checks.Add(new{name,pass});Console.WriteLine((pass?"PASS ":"FAIL ")+name);if(!pass)failures++;}
        var model=new PillMotion();
        model.Target(false,true,true);model.Target(true,true);model.Advance(.07);
        double position=model.Expansion,velocity=model.ExpansionVelocity;
        model.Target(false,true);
        Check("Reversing expansion preserves both position and velocity",model.Expansion==position&&model.ExpansionVelocity==velocity&&velocity>0);
        for(int i=0;i<180;i++){if(i%9==0)model.Target(i%18==0,true);model.Advance(1.0/144);}
        model.Target(false,true);for(int i=0;i<144;i++)model.Advance(1.0/144);
        Check("Rapid reversals settle back into the pill without a jump outside its endpoints",model.Expansion==0&&model.Presence==1&&!model.Moving);
        model.Target(true,true,true);model.Target(false,false);model.Advance(.019);
        Check("Mac close fades content immediately while retaining the first 20 ms of geometry",model.Width(2)==800&&model.Height(226)==226&&model.Top==0&&model.ContentOpacity<1&&model.ContentOpacity>0);
        model.Advance(.061);
        Check("Mac close contracts width and height together while attached to the top",model.Width(2)<800&&model.Width(2)>296&&model.Height(226)<226&&model.Height(226)>38&&model.Top==0&&model.PillShape==0&&model.PillOpacity==0);
        model.Advance(.021);
        Check("The expanded content and provider icons finish fading at 100 ms",model.ContentOpacity==0&&model.ProviderOpacity==0&&model.PillOpacity==0);
        double closeWidth=model.Width(2),closeHeight=model.Height(226),closeVelocity=model.CloseVelocity,closeOpacity=model.ProviderOpacity;
        model.Target(true,true);
        Check("Interrupting dismissal preserves geometry, opacity and spring velocity",model.Width(2)==closeWidth&&model.Height(226)==closeHeight&&model.CloseVelocity==closeVelocity&&model.ProviderOpacity==closeOpacity);
        for(int i=0;i<180;i++)model.Advance(1.0/144);
        Check("Interrupted dismissal settles back to the expanded header and original shape",model.Width(2)==800&&model.Height(226)==226&&model.Top==0&&model.PillShape==0&&model.ContentOpacity==1&&model.ProviderOpacity==1&&model.ShellOpacity==1&&!model.Moving);
        foreach(double height in new[]{226,277,335}) {
            model.PanelHeight=height;model.Target(true,true,true);model.Target(false,false);bool attached=true,noPill=true;double previousWidth=800;
            for(int i=0;i<120;i++) {
                model.Advance(1.0/144);
                if(model.ClosingAtEdge) {
                    attached&=model.Top==0&&model.Height(height)>=38&&model.Height(height)<=height&&model.Width(2)<=previousWidth;
                    noPill&=model.PillShape==0&&model.PillOpacity==0;previousWidth=model.Width(2);
                }
            }
            Check($"The {height:0} pixel panel contracts at the top edge without an intermediate pill",attached&&noPill);
            Check($"The {height:0} pixel panel disappears completely before the next hover",model.Top+model.Height(height)<0&&model.Expansion==0&&model.Presence==0&&!model.Moving);
        }
        foreach(double seconds in new[]{.025,.07,.14,.21}) {
            model.Target(true,true,true);model.Target(false,false);model.Advance(seconds);
            double width=model.Width(2),top=model.Top,opacity=model.ShellOpacity;
            model.Target(false,true);
            Check($"Returning to the pill during dismissal at {seconds*1000:0} ms starts continuously",model.Width(2)==width&&model.Top==top&&model.ShellOpacity==opacity);
            for(int i=0;i<180;i++)model.Advance(1.0/144);
            Check($"Returning at {seconds*1000:0} ms settles into the visible pill",model.Expansion==0&&model.Presence==1&&model.Top==12&&model.PillShape==1&&model.PillOpacity==1&&!model.Moving);
        }
        model.Target(false,true,true);Check("Reduced motion places the pill at its 12 pixel gap immediately",model.Top==12&&model.Expansion==0&&!model.Moving);
        model.Target(true,true,true);Check("Reduced motion expands flush to the top immediately",model.Top==0&&model.Expansion==1&&!model.Moving);
        model.Target(false,false,true);Check("Reduced motion hides immediately with no remaining animation",model.Presence==0&&!model.Moving);
        var progress=new List<double>();
        foreach(int rate in new[]{30,60,144}) {
            var cadence=new PillMotion();cadence.Target(false,true,true);cadence.Target(true,true);
            for(int i=0;i<rate/2;i++)cadence.Advance(1.0/rate);
            progress.Add(cadence.Expansion);
        }
        Check("30, 60 and 144 Hz converge to the same expanded endpoint",progress.All(p=>p==1));
        Check("Shared icons finish at the original Mac header positions",PillMotion.IconCenter(800,2,0,1)==new Point(34,19)&&PillMotion.IconCenter(800,2,1,1)==new Point(766,19)&&PillMotion.IconSize(1)==20);

        host.Child=null;
        var canvas=new Grid{Width=900,Height=360,ClipToBounds=true};host.Padding=new Thickness(0);host.Child=canvas;
        canvas.Children.Add(surface);surface.HorizontalAlignment=HorizontalAlignment.Center;surface.VerticalAlignment=VerticalAlignment.Top;
        var slide=new TranslateTransform();surface.RenderTransform=slide;
        var preferences=surface.Preferences;
        var captures=new List<object>();
        void Apply(PillMotion motion,bool expanded) {
            surface.Width=motion.Width(surface.Preferences.SelectedProviders.Length);surface.Height=motion.Height(226);
            slide.Y=motion.Top;surface.Expanded=expanded;surface.PillShape=motion.PillShape;surface.Opacity=motion.ShellOpacity;surface.ProviderOpacity=motion.ProviderOpacity;
            surface.PillOpacity=motion.PillOpacity;surface.ContentOpacity=motion.ContentOpacity;surface.Page=0;surface.PagePosition=0;surface.ChartStyle=4;
            surface.InvalidateVisual();
        }
        BitmapSource Raster() {
            host.UpdateLayout();var bitmap=new RenderTargetBitmap(1800,720,192,192,PixelFormats.Pbgra32);bitmap.Render(host);return bitmap;
        }
        void Save(BitmapSource bitmap,string name) {
            var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using var file=File.Create(Path.Combine(output,name+".png"));encoder.Save(file);
        }
        bool HasIcon(BitmapSource bitmap,Point center,double size,Color color) {
            var bytes=new byte[bitmap.PixelWidth*bitmap.PixelHeight*4];bitmap.CopyPixels(bytes,bitmap.PixelWidth*4,0);int count=0;
            for(int y=(int)((center.Y-size/2)*2);y<(center.Y+size/2)*2;y++)for(int x=(int)((center.X-size/2)*2);x<(center.X+size/2)*2;x++) {
                if(x<0||y<0||x>=bitmap.PixelWidth||y>=bitmap.PixelHeight)continue;
                int n=(y*bitmap.PixelWidth+x)*4;
                if(Math.Abs(bytes[n]-color.B)<15&&Math.Abs(bytes[n+1]-color.G)<15&&Math.Abs(bytes[n+2]-color.R)<15)count++;
            }
            return count>30;
        }
        bool OutsideClear(BitmapSource bitmap) {
            var bytes=new byte[bitmap.PixelWidth*bitmap.PixelHeight*4];bitmap.CopyPixels(bytes,bitmap.PixelWidth*4,0);
            double left=(900-surface.Width),right=(900+surface.Width),bottom=(slide.Y+surface.Height)*2;
            for(int y=0;y<bitmap.PixelHeight;y++)for(int x=0;x<bitmap.PixelWidth;x++) {
                if(x>=left-3&&x<=right+3&&y<=bottom+3)continue;
                int n=(y*bitmap.PixelWidth+x)*4;
                if(Math.Abs(bytes[n]-62)>1||Math.Abs(bytes[n+1]-46)>1||Math.Abs(bytes[n+2]-38)>1)return false;
            }
            return true;
        }
        foreach(int count in new[]{2,1}) {
            surface.Preferences=preferences with{RightProvider=count==1?null:preferences.RightProvider};
            var motion=new PillMotion();motion.Target(false,true,true);motion.Target(true,true);double prior=0;
            foreach(double seconds in new[]{0,.04,.08,.12,.20,.50}) {
                motion.Advance(seconds-prior);prior=seconds;Apply(motion,true);await Task.Delay(30);
                var bitmap=Raster();string name=$"morph-{count}-{seconds*1000:000}";Save(bitmap,name);
                var providers=surface.Preferences.SelectedProviders;
                bool intact=true;
                for(int i=0;i<count;i++) {
                    var center=PillMotion.IconCenter(surface.Width,count,i,motion.Expansion);
                    center.Offset((900-surface.Width)/2,slide.Y);
                    intact&=HasIcon(bitmap,center,PillMotion.IconSize(motion.Expansion),ParityData.Provider(providers[i]).Color);
                }
                Check($"{count} provider icons remain visible at {seconds*1000:0} ms of expansion",intact);
                Check($"Expanded content stays inside the growing {count} provider silhouette at {seconds*1000:0} ms",OutsideClear(bitmap));
                captures.Add(new{name,seconds,expansion=motion.Expansion,top=motion.Top,width=surface.Width});
            }
        }
        surface.Preferences=preferences;
        var departure=new PillMotion();departure.Target(true,true,true);departure.Target(false,false);double previousExit=0;
        foreach(double seconds in new[]{0,.02,.05,.10,.15,.22,.35,.50}) {
            departure.Advance(seconds-previousExit);previousExit=seconds;Apply(departure,false);await Task.Delay(30);
            Save(Raster(),$"mac-close-{seconds*1000:000}");
        }
        var animated=new PillMotion();animated.Target(false,true,true);Apply(animated,false);await Task.Delay(150);
        var intervals=new List<double>();
        async Task Animate(bool expand,bool show) {
            animated.Target(expand,show);var done=new TaskCompletionSource();long previous=Stopwatch.GetTimestamp();
            EventHandler? render=null;
            render=(_,_)=>{
                long now=Stopwatch.GetTimestamp();double elapsed=Stopwatch.GetElapsedTime(previous,now).TotalSeconds;
                if(elapsed<.001)return;previous=now;intervals.Add(elapsed*1000);
                animated.Advance(elapsed);Apply(animated,expand);
                if(!animated.Moving){CompositionTarget.Rendering-=render;done.SetResult();}
            };
            CompositionTarget.Rendering+=render;
            try{await done.Task.WaitAsync(TimeSpan.FromSeconds(3));}finally{CompositionTarget.Rendering-=render;}
        }
        await Animate(true,true);await Task.Delay(120);await Animate(false,false);await Animate(false,true);
        Check("The WPF render loop completes expansion, Mac-style dismissal and re-entry",animated.Presence==1&&animated.Expansion==0&&!animated.Moving);
        intervals.Sort();double Percentile(double p)=>intervals[(int)Math.Min(intervals.Count-1,Math.Floor(intervals.Count*p))];
        File.WriteAllText(Path.Combine(output,"motion-results.json"),JsonSerializer.Serialize(new{build=typeof(IslandVisual).Assembly.ManifestModule.ModuleVersionId,failures,checks,captures,renderFrames=intervals.Count,frameIntervalP50=Percentile(.5),frameIntervalP95=Percentile(.95)},new JsonSerializerOptions{WriteIndented=true}));
        if(failures>0)throw new Exception($"{failures} shared motion checks failed.");
    }
}
