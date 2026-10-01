using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace IslandPrototype;

internal sealed class NativeSqlite : IDisposable
{
    private nint handle;
    internal NativeSqlite(string path,bool readOnly=false)
    {
        int result=Api.sqlite3_open_v2(Utf8(path),out handle,readOnly?1:2|4|0x10000,0);
        if(result!=0){Dispose();throw new IOException("The local usage database could not be opened.");}
        Api.sqlite3_busy_timeout(handle,readOnly?500:5000);
    }
    internal static string Version=>Marshal.PtrToStringUTF8(Api.sqlite3_libversion())??"unknown";
    internal Statement Prepare(string sql)=>new(this,sql);
    internal void Execute(string sql,params object?[] values){using var statement=Prepare(sql);statement.Bind(values);while(statement.Read()){} }
    internal void BackupTo(string path)
    {
        using(File.Open(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)){}
        using var target=new NativeSqlite(path);
        nint backup=Api.sqlite3_backup_init(target.handle,Utf8("main"),handle,Utf8("main"));
        if(backup==0)throw new IOException("The usage-history backup could not start.");
        int result,finished;
        try {
            DateTime deadline=DateTime.UtcNow.AddSeconds(5);
            do {result=Api.sqlite3_backup_step(backup,256);if(result is 5 or 6)System.Threading.Thread.Sleep(10);}while(result is 0 or 5 or 6&&DateTime.UtcNow<deadline);
        } finally {finished=Api.sqlite3_backup_finish(backup);}
        if(result!=101||finished!=0)throw new IOException("The usage-history backup did not finish.");
        target.Execute("PRAGMA journal_mode=DELETE");
    }
    public void Dispose(){if(handle==0)return;Api.sqlite3_close_v2(handle);handle=0;}
    private static byte[] Utf8(string text)=>Encoding.UTF8.GetBytes(text+'\0');
    internal sealed class Statement : IDisposable
    {
        private nint statement;
        internal Statement(NativeSqlite db,string sql)
        {
            int result=Api.sqlite3_prepare_v2(db.handle,Utf8(sql),-1,out statement,0);
            if(result!=0){Dispose();throw new IOException("The local usage database query failed.");}
        }
        internal void Bind(params object?[] values)
        {
            Api.sqlite3_reset(statement);Api.sqlite3_clear_bindings(statement);
            for(int i=0;i<values.Length;i++) {
                int result=values[i] switch {
                    null=>Api.sqlite3_bind_null(statement,i+1),
                    string s=>Api.sqlite3_bind_text(statement,i+1,Utf8(s),Encoding.UTF8.GetByteCount(s),new nint(-1)),
                    long n=>Api.sqlite3_bind_int64(statement,i+1,n),
                    int n=>Api.sqlite3_bind_int64(statement,i+1,n),
                    double n=>Api.sqlite3_bind_double(statement,i+1,n),
                    byte[] b=>Api.sqlite3_bind_blob(statement,i+1,b,b.Length,new nint(-1)),
                    _=>throw new ArgumentException("Unsupported database value.")};
                if(result!=0)throw new IOException("The local usage database could not bind a value.");
            }
        }
        internal bool Read()
        {
            int result=Api.sqlite3_step(statement);
            return result switch {100=>true,101=>false,_=>throw new IOException("The local usage database operation failed.")};
        }
        internal long Long(int column)=>Api.sqlite3_column_int64(statement,column);
        internal double Double(int column)=>Api.sqlite3_column_double(statement,column);
        internal long Integer(int column)=>Api.sqlite3_column_type(statement,column)==1?Long(column):throw new IOException("The usage-history backup contains an invalid integer.");
        internal double Number(int column)=>Api.sqlite3_column_type(statement,column) is 1 or 2?Double(column):throw new IOException("The usage-history backup contains an invalid number.");
        internal string Text(int column,int maxBytes=2_097_152)
        {
            int count=Api.sqlite3_column_bytes(statement,column);
            if(count>maxBytes)throw new InvalidDataException("A local usage value is too large.");
            return Marshal.PtrToStringUTF8(Api.sqlite3_column_text(statement,column),count)??"";
        }
        internal byte[] Bytes(int column,int maxBytes=16_777_216)
        {
            int count=Api.sqlite3_column_bytes(statement,column);
            if(count>maxBytes)throw new InvalidDataException("A local usage record is too large.");
            byte[] result=new byte[count];if(count>0)Marshal.Copy(Api.sqlite3_column_blob(statement,column),result,0,count);return result;
        }
        public void Dispose(){if(statement==0)return;Api.sqlite3_finalize(statement);statement=0;}
    }
    private static class Api
    {
        private const string Dll="winsqlite3.dll";
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern nint sqlite3_libversion();
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_open_v2(byte[] path,out nint db,int flags,nint vfs);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_close_v2(nint db);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_busy_timeout(nint db,int milliseconds);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern nint sqlite3_backup_init(nint target,byte[] targetName,nint source,byte[] sourceName);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_backup_step(nint backup,int pages);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_backup_finish(nint backup);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_prepare_v2(nint db,byte[] sql,int count,out nint statement,nint tail);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_finalize(nint statement);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_reset(nint statement);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_clear_bindings(nint statement);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_step(nint statement);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_null(nint statement,int index);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_int64(nint statement,int index,long value);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_double(nint statement,int index,double value);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_text(nint statement,int index,byte[] text,int length,nint destructor);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_bind_blob(nint statement,int index,byte[] data,int length,nint destructor);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern long sqlite3_column_int64(nint statement,int column);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern double sqlite3_column_double(nint statement,int column);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_column_type(nint statement,int column);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern int sqlite3_column_bytes(nint statement,int column);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern nint sqlite3_column_text(nint statement,int column);
        [DllImport(Dll,CallingConvention=CallingConvention.Cdecl)] internal static extern nint sqlite3_column_blob(nint statement,int column);
    }
}
