using System;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using IslandPrototype;

string native=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),".grok","bin","grok.exe");
string before=Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(native)));
string compatible=await GrokCompatibility.PrepareAsync(native);
bool preserved=before==Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(native)));
bool ready=compatible!=native&&GrokCompatibility.Machine(compatible)==0x8664&&GrokCompatibility.Resolve(native)==compatible;
Console.WriteLine(JsonSerializer.Serialize(new {nativePreserved=preserved,compatibleReady=ready,nativeMachine=GrokCompatibility.Machine(native),compatibleMachine=GrokCompatibility.Machine(compatible)}));
if(!preserved||!ready)Environment.Exit(1);
