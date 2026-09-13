using System;

namespace IslandPrototype;

internal static class WakeScheduling
{
    internal static readonly TimeSpan OverdueSlack=TimeSpan.FromSeconds(120);
    internal static readonly TimeSpan GraceDelay=TimeSpan.FromSeconds(60);
    internal static bool IsOverdueFire(DateTimeOffset now,DateTimeOffset? expected)=>expected is DateTimeOffset due&&now-due>OverdueSlack;
}
