using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace IslandPrototype;

public sealed class CurrencyStore : IDisposable
{
    private sealed record RateCache(Dictionary<string,double> Rates,DateTimeOffset FetchedAt,DateTimeOffset SourceDate);
    private readonly HttpClient client;
    private readonly string path;
    private readonly CancellationTokenSource lifetime=new();
    private RateCache? cache;
    public string Selection {get;set;}="USD";
    public bool Refreshing {get;private set;}
    public string? Error {get;private set;}
    public DateTimeOffset? LastUpdated=>cache?.FetchedAt;
    public string DisplayCurrency=>Selection=="USD"||cache?.Rates.ContainsKey(Selection)==true?Selection:"USD";
    public string Symbol=>DisplayCurrency switch {"CNY" or "JPY"=>"¥","EUR"=>"€","GBP"=>"£","KRW"=>"₩","CAD"=>"C$","AUD"=>"A$","CHF"=>"CHF ",_=>"$"};
    public bool WholeUnits=>DisplayCurrency is "JPY" or "KRW";
    public double Rate=>cache?.Rates.GetValueOrDefault(DisplayCurrency,1)??1;
    public event Action? Changed;
    private static readonly string[] Supported=["USD","CNY","EUR","GBP","JPY","KRW","CAD","AUD","CHF"];

    public CurrencyStore(string path,HttpMessageHandler? handler=null)
    {
        this.path=path;client=handler==null?new HttpClient():new HttpClient(handler);
        client.Timeout=TimeSpan.FromSeconds(15);
        client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        try {
            if(File.Exists(path)) {
                var saved=JsonSerializer.Deserialize<RateCache>(File.ReadAllText(path));
                if(saved!=null&&Valid(saved.Rates))cache=saved;
            }
        } catch(Exception error) when(error is IOException or UnauthorizedAccessException or JsonException) {
            Error="Saved exchange rates could not be read. Displaying USD until rates refresh.";
        }
    }
    private static bool Valid(Dictionary<string,double> rates)=>rates.GetValueOrDefault("USD")==1&&Supported.All(id=>rates.TryGetValue(id,out double rate)&&double.IsFinite(rate)&&rate>0);
    public double Convert(double usd)=>usd*Rate;
    public string Format(double usd,bool symbol=true)
    {
        double value=Convert(usd);
        return (symbol?Symbol:"")+value.ToString(WholeUnits||value>=100?"N0":value>=10?"N1":"N2",Localizer.Culture);
    }
    public async Task RefreshAsync(bool force=false)
    {
        if(Refreshing||lifetime.IsCancellationRequested||(!force&&cache!=null&&DateTimeOffset.UtcNow-cache.FetchedAt<TimeSpan.FromDays(1)))return;
        Refreshing=true;Error=null;Changed?.Invoke();
        try {
            using var response=await client.GetAsync("https://open.er-api.com/v6/latest/USD",lifetime.Token);
            response.EnsureSuccessStatusCode();
            using var document=JsonDocument.Parse(await response.Content.ReadAsStringAsync(lifetime.Token));
            var data=document.RootElement;
            if(data.GetProperty("result").GetString()!="success"||data.GetProperty("base_code").GetString()!="USD")throw new InvalidDataException("Unexpected exchange-rate response.");
            var rates=data.GetProperty("rates").EnumerateObject().ToDictionary(p=>p.Name,p=>p.Value.GetDouble());
            if(!Valid(rates))throw new InvalidDataException("The exchange-rate response is incomplete.");
            var next=new RateCache(rates,DateTimeOffset.UtcNow,DateTimeOffset.FromUnixTimeSeconds(data.GetProperty("time_last_update_unix").GetInt64()));
            cache=next;
            string temporary=path+".tmp";
            try {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                await File.WriteAllTextAsync(temporary,JsonSerializer.Serialize(next),lifetime.Token);
                File.Move(temporary,path,true);
            } catch(Exception error) when(error is IOException or UnauthorizedAccessException) {
                Error="Rates refreshed, but could not be saved for offline use.";
                try {File.Delete(temporary);}catch(IOException){}catch(UnauthorizedAccessException){}
            }
        }
        catch(OperationCanceledException) when(lifetime.IsCancellationRequested){}
        catch(Exception error) when(error is HttpRequestException or JsonException or InvalidDataException or KeyNotFoundException or InvalidOperationException or FormatException or TaskCanceledException or ArgumentOutOfRangeException) {
            Error=cache==null?"Exchange rates are unavailable. Displaying USD.":"Could not refresh rates. Keeping the last saved rates.";
        }
        finally {Refreshing=false;if(!lifetime.IsCancellationRequested)Changed?.Invoke();}
    }
    public void Dispose(){lifetime.Cancel();client.Dispose();lifetime.Dispose();}
}
