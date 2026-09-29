using System;

namespace IslandPrototype;

internal sealed class PageScrollGesture
{
    private double lastPacket=double.NegativeInfinity;
    private int horizontal,vertical;
    private bool committed,horizontalCommit;
    private int direction;
    internal void Reset(){horizontal=vertical=0;committed=false;lastPacket=double.NegativeInfinity;direction=0;}
    internal int Push(int delta,bool isHorizontal,double milliseconds)
    {
        if(delta==0||!double.IsFinite(milliseconds))return 0;
        int normalized=isHorizontal?delta:-delta;
        if(milliseconds-lastPacket>180||milliseconds<lastPacket||committed&&horizontalCommit==isHorizontal&&Math.Sign(normalized)!=direction)Reset();
        lastPacket=milliseconds;
        if(committed)return 0;
        if(isHorizontal)horizontal=(int)Math.Clamp((long)horizontal+normalized,-1_000_000,1_000_000);
        else vertical=(int)Math.Clamp((long)vertical+normalized,-1_000_000,1_000_000);
        int value=Math.Abs(horizontal)>=Math.Abs(vertical)?horizontal:vertical;
        if(Math.Abs(value)<120)return 0;
        committed=true;horizontalCommit=Math.Abs(horizontal)>=Math.Abs(vertical);direction=Math.Sign(value);return direction;
    }
}
