// Test-only bridge. No PID, external handle or arbitrary privilege is accepted.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class GptrCurrentToken
{
    private const int MaxBytes = 65536;
    private const int MaxPrivileges = 256;
    private const uint Enabled = 2;
    private const uint Removed = 4;
    private IntPtr token = IntPtr.Zero;
    private readonly uint pid;
    private Entry[] original;
    private Entry[] targets;
    private Entry[] previous;
    private bool mustRestore;
    private bool closed;

    [StructLayout(LayoutKind.Sequential)]
    private struct Luid { public uint Low; public int High; }
    private struct Entry
    {
        public Luid Id;
        public uint Attributes;
    }
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentProcessId();
    [DllImport("kernel32.dll")]
    private static extern void SetLastError(uint error);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr handle);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenThreadToken(IntPtr thread, uint access,
        [MarshalAs(UnmanagedType.Bool)] bool asSelf, out IntPtr handle);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr handle, int kind,
        IntPtr buffer, int length, out int needed);
    [DllImport("advapi32.dll", EntryPoint = "LookupPrivilegeValueW", ExactSpelling = true,
        CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool LookupPrivilegeValue(string system, string name, out Luid id);
    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AdjustTokenPrivileges(IntPtr handle,
        [MarshalAs(UnmanagedType.Bool)] bool all, IntPtr state, int length,
        IntPtr oldState, out int needed);

    private static void Require(bool value)
    {
        if (!value) throw new InvalidOperationException("Owned token boundary");
    }
    private static ulong Key(Luid id)
    {
        return ((ulong)(uint)id.High << 32) | id.Low;
    }
    private static Entry[] Parse(byte[] bytes)
    {
        Require(bytes != null && bytes.Length >= 4 && bytes.Length <= MaxBytes);
        uint count = BitConverter.ToUInt32(bytes, 0);
        Require(count <= MaxPrivileges && bytes.Length == 4 + 12 * (int)count);
        Entry[] entries = new Entry[(int)count];
        HashSet<ulong> ids = new HashSet<ulong>();
        for (int i = 0; i < entries.Length; i++)
        {
            int offset = 4 + 12 * i;
            entries[i].Id.Low = BitConverter.ToUInt32(bytes, offset);
            entries[i].Id.High = BitConverter.ToInt32(bytes, offset + 4);
            entries[i].Attributes = BitConverter.ToUInt32(bytes, offset + 8);
            Require(ids.Add(Key(entries[i].Id)));
        }
        return entries;
    }
    private static byte[] Pack(Entry[] entries)
    {
        Require(entries != null && entries.Length <= MaxPrivileges);
        byte[] bytes = new byte[4 + 12 * entries.Length];
        Array.Copy(BitConverter.GetBytes((uint)entries.Length), 0, bytes, 0, 4);
        for (int i = 0; i < entries.Length; i++)
        {
            int offset = 4 + 12 * i;
            Array.Copy(BitConverter.GetBytes(entries[i].Id.Low), 0, bytes, offset, 4);
            Array.Copy(BitConverter.GetBytes(entries[i].Id.High), 0, bytes, offset + 4, 4);
            Array.Copy(BitConverter.GetBytes(entries[i].Attributes), 0, bytes, offset + 8, 4);
        }
        Parse(bytes);
        return bytes;
    }
    private static bool Equal(Entry[] a, Entry[] b)
    {
        if (a == null || b == null || a.Length != b.Length) return false;
        for (int i = 0; i < a.Length; i++)
            if (Key(a[i].Id) != Key(b[i].Id) || a[i].Attributes != b[i].Attributes)
                return false;
        return true;
    }
    private static int Find(Entry[] entries, Luid id)
    {
        for (int i = 0; i < entries.Length; i++)
            if (Key(entries[i].Id) == Key(id)) return i;
        throw new InvalidOperationException("Owned token boundary");
    }
    private static Entry[] Disabled(Entry[] entries, Entry[] selected)
    {
        Require(selected != null && selected.Length == 3);
        Entry[] changed = (Entry[])entries.Clone();
        HashSet<ulong> ids = new HashSet<ulong>();
        foreach (Entry target in selected)
        {
            Require(ids.Add(Key(target.Id)) && (target.Attributes & Enabled) != 0 &&
                (target.Attributes & Removed) == 0);
            int index = Find(entries, target.Id);
            Require(entries[index].Attributes == target.Attributes);
            changed[index].Attributes &= ~Enabled;
        }
        return changed;
    }
    private static void PreviousExact(Entry[] returned, Entry[] selected)
    {
        Require(returned != null && returned.Length == 3 && selected.Length == 3);
        foreach (Entry target in selected)
        {
            int index = Find(returned, target.Id);
            Require(returned[index].Attributes == target.Attributes);
        }
    }
    private static Entry[] DisableInput(Entry[] selected)
    {
        Require(selected != null && selected.Length == 3);
        Entry[] state = (Entry[])selected.Clone();
        for (int i = 0; i < state.Length; i++) state[i].Attributes = 0;
        return state;
    }
    private void Own()
    {
        Require(!closed && token != IntPtr.Zero && GetCurrentProcessId() == pid);
    }
    private byte[] Query(int kind)
    {
        Own();
        int needed;
        bool first = GetTokenInformation(token, kind, IntPtr.Zero, 0, out needed);
        int error = Marshal.GetLastWin32Error();
        Require(!first && error == 122 && needed >= 4 && needed <= MaxBytes);
        IntPtr buffer = Marshal.AllocHGlobal(needed);
        try
        {
            int actual;
            Require(GetTokenInformation(token, kind, buffer, needed, out actual) &&
                actual == needed);
            byte[] bytes = new byte[actual];
            Marshal.Copy(buffer, bytes, 0, actual);
            return bytes;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    public GptrCurrentToken()
    {
        pid = GetCurrentProcessId();
        IntPtr threadToken;
        bool impersonated = OpenThreadToken(GetCurrentThread(), 8, true, out threadToken);
        int error = Marshal.GetLastWin32Error();
        if (impersonated)
        {
            Require(threadToken != IntPtr.Zero && CloseHandle(threadToken));
            throw new InvalidOperationException("Owned token boundary");
        }
        Require(error == 1008 && threadToken == IntPtr.Zero);
        Require(OpenProcessToken(GetCurrentProcess(), 0x28, out token) &&
            token != IntPtr.Zero);
        try
        {
            byte[] kind = Query(8);
            Require(kind.Length == 4 && BitConverter.ToInt32(kind, 0) == 1);
            original = Parse(Query(3));
            string[] names = { "SeBackupPrivilege", "SeRestorePrivilege",
                "SeChangeNotifyPrivilege" };
            targets = new Entry[3];
            for (int i = 0; i < names.Length; i++)
            {
                Luid id;
                Require(LookupPrivilegeValue(null, names[i], out id));
                targets[i] = original[Find(original, id)];
            }
            Disabled(original, targets);
        }
        catch
        {
            IntPtr handle = token;
            token = IntPtr.Zero;
            closed = true;
            Require(CloseHandle(handle));
            throw;
        }
    }
    public void VerifyOriginal()
    {
        Require(Equal(Parse(Query(3)), original));
    }
    public void VerifyDisabled()
    {
        Require(Equal(Parse(Query(3)), Disabled(original, targets)));
    }
    public int[] StateCodes()
    {
        Entry[] now = Parse(Query(3));
        int[] values = new int[3];
        for (int i = 0; i < targets.Length; i++)
            values[i] = (now[Find(now, targets[i].Id)].Attributes & Enabled) == 0 ? 1 : 2;
        return values;
    }
    public void DisableGroup()
    {
        Own();
        Require(!mustRestore && previous == null);
        VerifyOriginal();
        Entry[] desired = DisableInput(targets);
        byte[] bytes = Pack(desired);
        IntPtr input = Marshal.AllocHGlobal(bytes.Length);
        IntPtr output = IntPtr.Zero;
        try
        {
            output = Marshal.AllocHGlobal(40);
            Marshal.Copy(bytes, 0, input, bytes.Length);
            mustRestore = true; // Armed before the only state-changing call.
            SetLastError(0);
            int needed;
            bool changed = AdjustTokenPrivileges(token, false, input, 40, output, out needed);
            int error = Marshal.GetLastWin32Error();
            Require(changed && error == 0 && needed == 40);
            byte[] old = new byte[needed];
            Marshal.Copy(output, old, 0, needed);
            Entry[] captured = Parse(old);
            PreviousExact(captured, targets);
            previous = captured;
            VerifyDisabled();
        }
        finally
        {
            if (output != IntPtr.Zero) Marshal.FreeHGlobal(output);
            Marshal.FreeHGlobal(input);
        }
    }
    public void Restore()
    {
        Own();
        if (mustRestore)
        {
            // A captured full original snapshot covers partial native failure too.
            Entry[] saved = previous == null ? targets : previous;
            PreviousExact(saved, targets);
            byte[] bytes = Pack(saved);
            IntPtr input = Marshal.AllocHGlobal(bytes.Length);
            try
            {
                Marshal.Copy(bytes, 0, input, bytes.Length);
                SetLastError(0);
                int needed;
                bool restored = AdjustTokenPrivileges(token, false, input, 0,
                    IntPtr.Zero, out needed);
                int error = Marshal.GetLastWin32Error();
                Require(restored && error == 0);
            }
            finally { Marshal.FreeHGlobal(input); }
        }
        VerifyOriginal(); // Every call queries again, including a second finally call.
        mustRestore = false;
    }
    public void Close()
    {
        Own();
        IntPtr handle = token;
        token = IntPtr.Zero;
        closed = true;
        Require(CloseHandle(handle));
    }
    private static bool Rejected(Action action)
    {
        try { action(); return false; }
        catch (InvalidOperationException) { return true; }
    }
    public static int PureChecks()
    {
        // No constructor, token handle, P/Invoke or filesystem operation is used here.
        Entry[] seed = new Entry[4];
        for (int i = 0; i < seed.Length; i++)
        {
            seed[i].Id.Low = (uint)(i + 1);
            seed[i].Attributes = 3;
        }
        Entry[] group = { seed[0], seed[1], seed[2] };
        byte[] bytes = Pack(seed);
        int passed = 0;
        Require(Equal(Parse(bytes), seed)); passed++;
        Require(Rejected(delegate { Parse(new byte[3]); })); passed++;
        byte[] largeCount = (byte[])bytes.Clone();
        Array.Copy(BitConverter.GetBytes((uint)257), largeCount, 4);
        Require(Rejected(delegate { Parse(largeCount); })); passed++;
        Require(Rejected(delegate { Parse(new byte[52 + 1]); })); passed++;
        Entry[] duplicate = (Entry[])seed.Clone(); duplicate[3].Id = duplicate[0].Id;
        Require(Rejected(delegate { Pack(duplicate); })); passed++;
        Entry[] disabled = Disabled(seed, group);
        Entry[] input = Parse(Pack(DisableInput(group)));
        Require(disabled[0].Attributes == 1 && disabled[1].Attributes == 1 &&
            disabled[2].Attributes == 1 && disabled[3].Attributes == 3 &&
            input[0].Attributes == 0 && input[1].Attributes == 0 &&
            input[2].Attributes == 0 && Equal(seed, Parse(bytes))); passed++;
        Entry[] missing = (Entry[])group.Clone(); missing[2].Id.Low = 100;
        Require(Rejected(delegate { Disabled(seed, missing); })); passed++;
        Entry[] repeated = (Entry[])group.Clone(); repeated[2] = repeated[0];
        Require(Rejected(delegate { Disabled(seed, repeated); })); passed++;
        Entry[] wrongPrevious = (Entry[])group.Clone(); wrongPrevious[1].Attributes = 1;
        Require(Rejected(delegate { PreviousExact(wrongPrevious, group); })); passed++;
        Entry[] foreignChange = (Entry[])disabled.Clone(); foreignChange[3].Attributes = 1;
        Require(!Equal(foreignChange, Disabled(seed, group)) &&
            Equal(Parse(Pack(group)), group)); passed++;
        return passed;
    }
}
