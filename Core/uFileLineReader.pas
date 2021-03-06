unit uFileLineReader;

interface

uses
	uTypes,
	SysUtils;

type
	TFileLineReader = class
	private
		FStop: BG;
		FFileName: TFileName;
	protected
		procedure ReadLine(const Line: string); virtual; abstract;
	public
		constructor Create(const FileName: TFileName);
		procedure Parse;
		procedure Stop;
	end;

implementation

uses uFile;

{ TFileLineReader }

constructor TFileLineReader.Create(const FileName: TFileName);
begin
	FFileName := FileName;
end;

procedure TFileLineReader.Parse;
var
	F: TFile;
	Line: string;
begin
	F := TFile.Create;
	try
		if F.Open(FFileName, fmReadOnly) then
		begin
			FStop := False;
			while (not F.Eof) and (FStop = False) do
			begin
				F.Readln(Line);
				ReadLine(Line);
			end;
			F.Close;
		end;
	finally
		F.Free;
	end;
end;

procedure TFileLineReader.Stop;
begin
	FStop := True;
end;

end.
