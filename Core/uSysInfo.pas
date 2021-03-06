unit uSysInfo;

interface

uses
	uTypes, uMath,
	Windows, Messages, SysUtils;

const
	CPUUsageMul = 100;
const
	CPUStrOffset = 4 + 4 + 1;
type
  {$if CompilerVersion < 20}
  DWORDLONG = S8;
  PMemoryStatusEx = ^TMemoryStatusEx;
  LPMEMORYSTATUSEX = PMemoryStatusEx;
  {$EXTERNALSYM LPMEMORYSTATUSEX}
  _MEMORYSTATUSEX = packed record
    dwLength : DWORD;
    dwMemoryLoad : DWORD;
    ullTotalPhys : DWORDLONG;
    ullAvailPhys : DWORDLONG;
    ullTotalPageFile: DWORDLONG;
    ullAvailPageFile: DWORDLONG;
    ullTotalVirtual : DWORDLONG;
    ullAvailVirtual : DWORDLONG;
    ullAvailExtendedVirtual : DWORDLONG;
  end;
  {$EXTERNALSYM _MEMORYSTATUSEX}
  TMemoryStatusEx = _MEMORYSTATUSEX;
  MEMORYSTATUSEX = _MEMORYSTATUSEX;
  {$EXTERNALSYM MEMORYSTATUSEX}
  {$ifend}

	PSysInfo = ^TSysInfo;
	TSysInfo = packed record // 256
		CPU: U4;
		CPU2: U4;
		CPUStr: string[12]; // 13
		LogicalProcessorCount: SG;
		Reserved0: array[0..2] of S1; // 3
		CPUFrequency: U8; // precision 0,00041666 (0.1s/4min, 1.5s/1hod. 36sec/24hod)
		CPUPower: U8;
		PerformanceFrequency: U4;
//		DiskFree, DiskTotal: U8; // 16
//		Reserved: array[0..3] of U4; // 16
		CPUUsage: S4; // 4 (0..10000)
		MS: TMemoryStatusEx; // 8 * 8 = 64
		OS: TOSVersionInfo; // 148
//		ProgramVersion: string[15]; // 10.32.101.10000
//		Graph: string[127]; // 128
//		Reserved1: array[0..15] of U1; // 16
	end;

var
	GSysInfo: TSysInfo;
	NTSystem: Boolean;
	Aero: Boolean;
	RegionCompatibily: Boolean;

function GetKey(Default: U2): U2;
function OSToStr(const OS: TOSVersionInfo): string;
function GetCPUUsage: SG;
procedure FillDynamicInfo(var SysInfo: TSysInfo); // FillMemoryStatus + FillCPUTest
procedure FillMemoryStatus(var SysInfo: TSysInfo);
procedure FillCPUTest(var SysInfo: TSysInfo);
procedure DelayEx(const f: U8);

//function MMUsedMemory: U8;
function MaxPhysicalMemorySize: U8;
function ProcessAllocatedVirtualMemory: U8;
function CanAllocateMemory(const Size: UG): BG;

implementation

uses
//  FastMM4,
  PsAPI,
  uMsg,
	uStrings, uOutputFormat, uSimulation, uDictionary,
	uProjectInfo,
	Registry, Math;

{$if CompilerVersion < 20}
procedure GlobalMemoryStatus(var lpBuffer: TMemoryStatus); stdcall;
  external kernel32;
{$EXTERNALSYM GlobalMemoryStatus}

function GlobalMemoryStatusEx(var lpBuffer: TMemoryStatusEx): BOOL; stdcall;
type
  TFNGlobalMemoryStatusEx = function(var msx: TMemoryStatusEx): BOOL; stdcall;
var
  FNGlobalMemoryStatusEx: TFNGlobalMemoryStatusEx;
begin
  FNGlobalMemoryStatusEx := TFNGlobalMemoryStatusEx(
    GetProcAddress(GetModuleHandle(kernel32), 'GlobalMemoryStatusEx'));
  if not Assigned(FNGlobalMemoryStatusEx) then
  begin
    SetLastError(ERROR_CALL_NOT_IMPLEMENTED);
    Result := False;
  end
  else
  begin
    Result := FNGlobalMemoryStatusEx(lpBuffer);
  end;
end;
{$ifend}

function GetKey(Default: U2): U2;
var
	Keyboard: TKeyboardState;
	i: Integer;
begin
	while True do
	begin
		GetKeyboardState(Keyboard);
		for i := Low(Keyboard) to High(Keyboard) do
		begin
			if (Keyboard[i] and $80 <> 0) and (i <> VK_LBUTTON) and (i <> VK_RBUTTON)
			and (i <> VK_MBUTTON) then
			begin
				Result := i;
				if (not NTSystem) or (not (i in [VK_SHIFT, VK_CONTROL, VK_MENU])) then Exit;
			end;
		end;
	end;
end;

function OSToStr(const OS: TOSVersionInfo): string;
{$ifndef UNICODE}
const
	VER_PLATFORM_WIN32_CE = 3;
{$endif}
var S: string;
begin
	case OS.dwPlatformId of
	VER_PLATFORM_WIN32s: // 0
		S := 'Win32';
	VER_PLATFORM_WIN32_WINDOWS: // 1
	begin
		S := 'Windows ';
		if (OS.dwMajorVersion < 4) or ((OS.dwMajorVersion = 4) and (OS.dwMinorVersion < 10)) then
			S := S + '95'
		else
			S := S + '98';
	end;
	VER_PLATFORM_WIN32_NT: // 2
	begin
		S := 'Windows ';
		if OS.dwMajorVersion < 5 then
			S := S + 'NT'
		else if OS.dwMajorVersion < 6 then
		begin
			if OS.dwMinorVersion = 0 then
				S := S + '2000'
			else
				S := S + 'XP';
		end
		else if OS.dwMajorVersion = 6 then
		begin
			case OS.dwMinorVersion of
			0: S := S + 'Vista';
      1: S := S + '7';
      2: S := S + '8';
      3: S := S + '8.1';
      else S := S + '10';
      end;
		end
		else // if OS.dwMajorVersion = 10 then
      S := S + IntToStr(OS.dwMajorVersion);
	end;
	VER_PLATFORM_WIN32_CE: // 3
		S := 'Windows CE'
	else // 3
		S := 'Unknown System ' + IntToStr(OS.dwPlatformId - VER_PLATFORM_WIN32_NT);
	end;
	S := S + ' (Build ' +
		IntToStr(OS.dwMajorVersion) + '.' +
		IntToStr(OS.dwMinorVersion) + '.' +
		IntToStr(LoWord(OS.dwBuildNumber)) + ' ' +
		OS.szCSDVersion + ')';
	Result := S;
end;

procedure FillMemoryStatus(var SysInfo: TSysInfo);
begin
	SysInfo.MS.dwLength := SizeOf(SysInfo.MS);
	GlobalMemoryStatusEx(SysInfo.MS);
end;

const
//	SystemBasicInformation = 0;
  SystemPerformanceInformation = 2;
  SystemTimeInformation = 3;

type
  TPDWord = ^DWORD;
{
	TSystem_Basic_Information = packed record
    dwUnknown1: DWORD;
    uKeMaximumIncrement: ULONG;
    uPageSize: ULONG;
		uMmNumberOfPhysicalPages: ULONG;
		uMmLowestPhysicalPage: ULONG;
		uMmHighestPhysicalPage: ULONG;
		uAllocationGranularity: ULONG;
		pLowestUserAddress: Pointer;
		pMmHighestUserAddress: Pointer;
		uKeActiveProcessors: ULONG;
		bKeNumberProcessors: byte;
		bUnknown2: byte;
		wUnknown3: word;
	end;}

type
	TSystem_Performance_Information = packed record
		liIdleTime: LARGE_INTEGER;
		dwSpare: array[0..75] of DWORD;
	end;

type
	TSystem_Time_Information = packed record
		liKeBootTime: LARGE_INTEGER;
		liKeSystemTime: LARGE_INTEGER;
		liExpTimeZoneBias: LARGE_INTEGER;
		uCurrentTimeZoneId: ULONG;
		dwReserved: DWORD;
	end;

var
	NtQuerySystemInformation: function(infoClass: DWORD;
		buffer: Pointer;
		bufSize: DWORD;
		returnSize: TPDword): DWORD; stdcall = nil;


	liOldIdleTime: LARGE_INTEGER = ();
	liOldSystemTime: LARGE_INTEGER = ();

{function Li2Double(x: LARGE_INTEGER): Double;
begin
	Result := x.HighPart * 4.294967296E9 + x.LowPart
end;}

function GetLogicalProcessorCount: SG;
var
  SystemInfo: SYSTEM_INFO;
begin
  // get number of processors in the system
  GetSystemInfo(SystemInfo);
  Result := SystemInfo.dwNumberOfProcessors;
end;

var
	CPUUsage: SG;

function GetCPUUsageForce: SG;
var
  SystemInfo: SYSTEM_INFO;
	SysPerfInfo: TSystem_Performance_Information;
	SysTimeInfo: TSystem_Time_Information;
	status: DWORD;
	dbSystemTime: U8;
	dbIdleTime: U8;
//	s: string;
begin
	Result := 0;

	if Pointer(@NtQuerySystemInformation) = nil then
    Exit;

  GetSystemInfo(SystemInfo);

		// get new system time
	status := NtQuerySystemInformation(SystemTimeInformation, @SysTimeInfo, SizeOf(SysTimeInfo), nil);
	if status <> 0 then Exit;

	// get new CPU's idle time
	status := NtQuerySystemInformation(SystemPerformanceInformation, @SysPerfInfo, SizeOf(SysPerfInfo), nil);
	if status <> 0 then Exit;

	// if it's a first call - skip it
	if (liOldIdleTime.QuadPart <> 0) then
	begin

		// CurrentValue = NewValue - OldValue
		dbIdleTime := SysPerfInfo.liIdleTime.QuadPart - liOldIdleTime.QuadPart;
		dbSystemTime := SysTimeInfo.liKeSystemTime.QuadPart - liOldSystemTime.QuadPart;

		// CurrentCpuIdle = IdleTime / SystemTime

		// CurrentCpuUsage% = 100 - (CurrentCpuIdle * 100) / NumberOfProcessors
    if dbSystemTime = 0 then
      Result := 0
    else
    begin
    		Result := Round(CPUUsageMul * (100.0 - (dbIdleTime / dbSystemTime) * 100.0 / SystemInfo.dwNumberOfProcessors));
  		Result := Range(0, Result, 100 * CPUUsageMul);
    end;

		// Show Percentage
//		Result := RoundN(100 * dbIdleTime);
	end;

		// store new CPU's idle and system time
		liOldIdleTime := SysPerfInfo.liIdleTime;
		liOldSystemTime := SysTimeInfo.liKeSystemTime;
end;

(*
function GetProcessorTime : int64;
type
	TPerfDataBlock = packed record
		signature              : array [0..3] of wchar;
		littleEndian           : U4;
		version                : U4;
		revision               : U4;
		totalByteLength        : U4;
		headerLength           : U4;
		numObjectTypes         : S4;
		defaultObject          : U4;
		systemTime             : TSystemTime;
		perfTime               : S8;
		perfFreq               : S8;
		perfTime100nSec        : S8;
		systemNameLength       : U4;
		systemnameOffset       : U4;
	end;
	TPerfObjectType = packed record
		totalByteLength        : U4;
		definitionLength       : U4;
		headerLength           : U4;
		objectNameTitleIndex   : U4;
		objectNameTitle        : PWideChar;
		objectHelpTitleIndex   : U4;
		objectHelpTitle        : PWideChar;
		detailLevel            : U4;
		numCounters            : S4;
		defaultCounter         : S4;
		numInstances           : S4;
		codePage               : U4;
		perfTime               : S8;
		perfFreq               : S8;
	end;
	TPerfCounterDefinition = packed record
		byteLength             : U4;
		counterNameTitleIndex  : U4;
		counterNameTitle       : PWideChar;
		counterHelpTitleIndex  : U4;
		counterHelpTitle       : PWideChar;
		defaultScale           : S4;
		defaultLevel           : U4;
		counterType            : U4;
		counterSize            : U4;
		counterOffset          : U4;
	end;
	TPerfInstanceDefinition = packed record
		byteLength             : U4;
		parentObjectTitleIndex : U4;
		parentObjectInstance   : U4;
		uniqueID               : S4;
		nameOffset             : U4;
		nameLength             : U4;
	end;
var
	c1, c2, c3      : U4;
	i1, i2          : S4;
	perfDataBlock   : ^TPerfDataBlock;
	perfObjectType  : ^TPerfObjectType;
	perfCounterDef  : ^TPerfCounterDefinition;
	perfInstanceDef : ^TPerfInstanceDefinition;
begin
	result := 0;
	perfDataBlock := nil;
	try
		c1 := $10000;
		while True do 
		begin
			ReallocMem(perfDataBlock, c1);
			c2 := c1;
			case RegQueryValueEx(HKEY_PERFORMANCE_DATA, '238'{'Processor/Processor Time'}, nil, @c3, Pointer(perfDataBlock), @c2) of
			ERROR_MORE_DATA: c1 := c1 * 2;
			ERROR_SUCCESS: Break;
			else Exit;
			end;
		end;
		perfObjectType := Pointer(UG(perfDataBlock) + perfDataBlock^.headerLength);
		for i1 := 0 to perfDataBlock^.numObjectTypes - 1 do
		begin
			if perfObjectType^.objectNameTitleIndex = 238 then
			begin   // 238 -> "Processor"
				perfCounterDef := Pointer(UG(perfObjectType) + perfObjectType^.headerLength);
				for i2 := 0 to perfObjectType^.numCounters - 1 do
				begin
					if perfCounterDef^.counterNameTitleIndex = 6 then
					begin    // 6 -> "% Processor Time"
						perfInstanceDef := Pointer(UG(perfObjectType) + perfObjectType^.definitionLength);
						result := PS8(UG(perfInstanceDef) + perfInstanceDef^.byteLength + perfCounterDef^.counterOffset)^;
						break;
					end;
					inc(perfCounterDef);
				end;
				break;
			end;
			perfObjectType := Pointer(UG(perfObjectType) + perfObjectType^.totalByteLength);
		end;
	finally
		FreeMem(perfDataBlock);
	end;
end;
*)
var
	Reg: TRegistry;
	LastTickCount{, LastProcessorTime}: U8;

function GetCPUUsage: SG;
const
	IntervalTime = Second div 2;
var
	tickCount     : U8;
//	processorTime : U8;
	Dummy: array[0..KB] of U1;
begin
	if NTSystem then
	begin
//		tickCount := GetTickCount;
		tickCount := PerformanceCounter;
		if tickCount < LastTickCount then
		begin
			// Possible after hibernation or overflow
			LastTickCount := tickCount;
		end;
		if tickCount < LastTickCount + IntervalTime then
		begin
			Result := CPUUsage;
			Exit;
		end;
//		processorTime := GetProcessorTime;

		if {(LastTickCount <> 0) and} (tickCount > LastTickCount) {and (processorTime >= LastProcessorTime)} then
		begin // 1 000 * 10 000 = 10 000 000 / sec
(*			CPUUsage := 100 * CPUUsageMul - RoundDivS8(PerformanceFrequency * (processorTime - LastProcessorTime), 1000 * (tickCount - LastTickCount){ + 1}) ;
			CPUUsage := Range(0, CPUUsage, 100 * CPUUsageMul);}*)
			CPUUsage := GetCPUUsageForce;
		end;

		Result := CPUUsage;

		LastTickCount     := tickCount;
//		LastProcessorTime := processorTime;
	end
	else
	begin
		Result := CPUUsage;
		if Reg = nil then
		begin
			Reg := TRegistry.Create(KEY_QUERY_VALUE);
			Reg.RootKey := HKEY_DYN_DATA;
//			Reg.CreateKey('PerfStats');
			if Reg.OpenKeyReadOnly('PerfStats\StartStat') then
			begin
				Reg.ReadBinaryData('KERNEL\CPUUsage', Dummy, SizeOf(Dummy));
				Reg.ReadBinaryData('KERNEL\CPUUsage', CPUUsage, SizeOf(CPUUsage));
				Reg.CloseKey;
			end;

			if Reg.OpenKeyReadOnly('PerfStats\StatData') then
			begin
				Reg.ReadBinaryData('KERNEL\CPUUsage', CPUUsage, SizeOf(CPUUsage));
				Result := CPUUsageMul * CPUUsage;
				Reg.CloseKey;
			end;
		end;

		if Reg.OpenKeyReadOnly('PerfStats\StatData') then
		begin
			Reg.ReadBinaryData('KERNEL\CPUUsage', CPUUsage, SizeOf(CPUUsage));
			Result := CPUUsageMul * CPUUsage;
			Reg.CloseKey;
		end;
	end;
end;

procedure FillCPUID(var SysInfo: TSysInfo);
asm
{$ifdef CPUX64}
  push rax
  push rbx
  push rcx
  push rdx
  push rdi
  mov rdi, SysInfo{rcx}
  xor rax, rax
  xor rbx, rbx
  xor rcx, rcx
  xor rdx, rdx
  cpuid
  mov rax, rdi
  add rax, CPUStrOffset
  mov [rax], ebx
  mov [rax+4], edx
  mov [rax+8], ecx

  mov eax, 1
  xor ebx, ebx
  xor ecx, ecx
  xor edx, edx
  cpuid

  mov rdx, rdi
  mov [rdx], eax
  mov [rdx+4], ebx
  pop rdi
  pop rdx
  pop rcx
  pop rbx
  pop rax
{$else}
  pushad
  mov edi, SysInfo{ecx}
  xor eax, eax
  xor ebx, ebx
  xor ecx, ecx
  xor edx, edx
  dw 0a20fh // cpuid
  mov eax, edi{SysInfo}
  add eax, CPUStrOffset
  mov [eax], ebx
  mov [eax+4], edx
  mov [eax+8], ecx

  mov eax, 1
  xor ebx, ebx
  xor ecx, ecx
  xor edx, edx
  dw 0a20fh // cpuid

  mov edx, edi{SysInfo}
  mov [edx], eax
  mov [edx+4], ebx
  popad
{$endif}
end;

{$ifdef CPUX64}
procedure Loop(PMem: Pointer; MaxMem4: NativeInt; Count: NativeInt);
asm
  push rax
  push rbx
  push rcx
  push rdi
  mov rdi, PMem{rcx}
  mov rcx, Count
  sub rcx, 1
  @Loop:
    mov rax, rcx
    and rax, MaxMem4
    mov [rdi+8*rax], rbx
    sub rcx, 1
  jnz @Loop
  pop rdi
  pop rcx
  pop rbx
  pop rax
{
      j := 0;
      while j < Count do
      begin
        PDWORD(PByte(PMem) + (SizeOf(Pointer) * j) and MaxMem4)^ := j;
        Inc(j);
      end;}
end;
{$endif}

procedure FillCPUTest(var SysInfo: TSysInfo);
var
	TickCount: U8;
	CPUTick: U8;
const
	Count = 1 shl 22;
var
	MaxMem4, MaxMem: UG;
	PMem: Pointer;
begin
  MaxMem4 :=  1 shl 14 - 1; {10 = 4kB; 14 = 64kB}
  MaxMem := SizeOf(Pointer) * (MaxMem4 + 1) - 1;
  GetMem(PMem, MaxMem + 1);
  try
    SetPriorityClass(GetCurrentProcess, REALTIME_PRIORITY_CLASS);
    try
      TickCount := PerformanceCounter;
      CPUTick := GetCPUCounter.A;
{$ifdef CPUX64}
      Loop(PMem, MaxMem4, Count div 2);
{$else}
      asm
      pushad

{     mov ecx, 999 // 1M

      @Loop:
        mov edi, U4 ptr PMem
        mov esi, U4 ptr PMem2
        push ecx
        mov ecx, 32768
        shr ecx, 2
        cld
          rep movsd
        pop ecx
        sub ecx, 1
      jnz @Loop}
(*
      mov ecx, 999998 // 1M
//      mov edi, U4 ptr PMem
      @Loop: // 3 - Duron, 4 - P4
        mov esi, edi
        mov ebx, ecx
        and ebx, 32767
        add esi, ebx
//        mov [esi], cl
        sub ecx, 1
      jnz @Loop*)

      mov ecx, Count - 1 // 1M
      mov edi, PMem
      @Loop: // 4 clocks
        mov eax, ecx
        mov esi, edi
        and eax, MaxMem4
        sub ecx, 1
        mov [esi+4*eax], ebx
      jnz @Loop

      popad
      end;
{$endif}
      CPUTick := GetCPUCounter.A - CPUTick;
      TickCount := PerformanceCounter - TickCount;
      if (TickCount > 0) and (CPUTick < High(Int64) div (2 * PerformanceFrequency)) then
      begin
        SysInfo.CPUFrequency := RoundDivS8(CPUTick * PerformanceFrequency, TickCount);
        SysInfo.CPUPower := RoundDivS8(4 * Count * PerformanceFrequency, TickCount);
      end
      else
      begin
        SysInfo.CPUFrequency := 0;
        SysInfo.CPUPower := 0;
      end;
    except
      SysInfo.CPUFrequency := 0;
      SysInfo.CPUPower := 0;
    end;
  finally
    SetPriorityClass(GetCurrentProcess, NORMAL_PRIORITY_CLASS);
    FreeMem(PMem);
	end;
end;

procedure FillDynamicInfo(var SysInfo: TSysInfo);
begin
	FillMemoryStatus(SysInfo);
	SysInfo.CPUUsage := GetCPUUsage;
	FillCPUTest(SysInfo);
end;

{
function GetCpuSpeed: string;
var
	Reg: TRegistry;
begin
	Reg := TRegistry.Create(KEY_QUERY_VALUE);
try
	Reg.RootKey := HKEY_LOCAL_MACHINE;
	if Reg.OpenKeyReadOnly('Hardware\Description\System\CentralProcessor\0', False) then
	begin
		Result := IntToStr(Reg.ReadInteger('~MHz')) + ' MHz';
		Reg.CloseKey;
	end;
	finally
		Reg.Free;
	end;
end;
}

procedure Init;
begin
	GSysInfo.OS.dwOSVersionInfoSize := SizeOf(GSysInfo.OS);
	GetVersionEx(GSysInfo.OS);
	NTSystem := GSysInfo.OS.dwMajorVersion >= 5;
  Aero := GSysInfo.OS.dwMajorVersion >= 6; // >= Vista
	RegionCompatibily := not ((GSysInfo.OS.dwMajorVersion < 4) or ((GSysInfo.OS.dwMajorVersion = 4) and (GSysInfo.OS.dwMinorVersion < 10)));

	NtQuerySystemInformation := GetProcAddress(GetModuleHandle('ntdll.dll'), 'NtQuerySystemInformation');

	InitPerformanceCounter;
	GSysInfo.CPUStr := '            '; //StringOfChar(CharSpace, 12);
	FillCPUID(GSysInfo);
	GSysInfo.LogicalProcessorCount := GetLogicalProcessorCount;
{	PerformanceType := ptCPU;
	FillCPUTest(GSysInfo);
	PerformanceFrequency := GSysInfo.CPUFrequency;}

	GSysInfo.PerformanceFrequency := PerformanceFrequency;

//	GSysInfo.ProgramVersion := GetProjectInfo(piProductVersion);

	CPUUsage := 0 * CPUUsageMul;
	GetCPUUsage;
end;

procedure Nop; assembler;
asm
  nop
end;

procedure DelayEx(const f: U8);
var
	TickCount: U8;
	i: SG;
begin
	TickCount := PerformanceCounter + f;
	while PerformanceCounter < TickCount do
	begin
		for i := 0 to Min(1000, GSysInfo.CPUFrequency div 40) - 1 do
		begin
      Nop;
		end;
	end;
end;

//function MMUsedMemory: U8;
//var
//    st: TMemoryManagerState;
//    sb: TSmallBlockTypeState;
//    i: SG;
//begin
//  GetMemoryManagerState(st);
//  Result := st.TotalAllocatedMediumBlockSize + st.TotalAllocatedLargeBlockSize;
//  for i := Low(st.SmallBlockTypeStates) to High(st.SmallBlockTypeStates) do
//  begin
//    sb := st.SmallBlockTypeStates[i];
//      Inc(Result, sb.UseableBlockSize * sb.AllocatedBlockCount);
//  end;
//end;

function ProcessAllocatedVirtualMemory: U8;
var
  MemCounters: TProcessMemoryCounters;
begin
  MemCounters.cb := SizeOf(MemCounters);
  Result := 0;
  if GetProcessMemoryInfo(GetCurrentProcess,
      @MemCounters,
      SizeOf(MemCounters)) then
  begin
    // MemCounters.PagefileUsage is defined as SIZE_T (size is 4 bytes in 32 bit version and 8 bytes in 64 bit version)
    Result := MemCounters.PagefileUsage;
  end
  else
    RaiseLastOSError;
end;

function MaxPhysicalMemorySize: U8;
begin
	FillMemoryStatus(GSysInfo);
  Result := Min(2 * GSysInfo.MS.ullTotalPhys div 3 {66%}, GSysInfo.MS.ullTotalVirtual);
end;

function MaxAllocationSize: U8;
begin
	FillMemoryStatus(GSysInfo);
  Result := Max(0, MaxPhysicalMemorySize - ProcessAllocatedVirtualMemory);

  Result := 2 * Result div 3; // Fragmentation
end;

const
  ReservedSize = 8 * MB;

function CanAllocateMemory(const Size: UG): BG;
var
  P: Pointer;
begin
//  Result := Size + ReservedSize < MaxAllocationSize;
  try
    GetMem(P, Size + ReservedSize);
    Result := P <> nil;
    FreeMem(P);
  except
    Result := False;
  end;
end;

initialization
{$IFNDEF NoInitialization}
	Init;
{$ENDIF NoInitialization}
finalization
{$IFNDEF NoFinalization}
//	FreeAndNil(fSysInfo);
	if NTSystem = False then
	begin
		if Reg <> nil then
		begin
			if Reg.OpenKey('PerfStats\StopStat', False) then
			begin
				Reg.ReadBinaryData('KERNEL\CPUUsage', CPUUsage, SizeOf(CPUUsage));
				Reg.CloseKey;
			end;

			FreeAndNil(Reg);
		end;
	end;
{$ENDIF NoFinalization}
end.
