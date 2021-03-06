unit uConsole;

interface

type
  TConsoleColor = (
    ccBlack, ccBlue, ccGreen, ccAquq, ccRed, ccPurple, ccYellow, ccLightGray,
    ccGray, ccLightBlue, ccLightGreen, ccLightAqua, ccLightRed, ccLightPurple, ccLightYellow, ccWhite);

  TConsole = class
    class procedure WriteLine(const Text: string); overload;
    class procedure WriteLine(const Text: string; const ForegroundColor: TConsoleColor; const BackgroundColor: TConsoleColor = ccBlack); overload;
  end;

implementation

uses
  uTypes,
  uCharset,
  Windows;

class procedure TConsole.WriteLine(const Text: string);
begin
  {$ifdef UNICODE}
  Writeln(Text);
  {$else}
  Writeln(ConvertAnsiToOem(Text));
  {$endif}
end;

class procedure TConsole.WriteLine(const Text: string; const ForegroundColor, BackgroundColor: TConsoleColor);
begin
    SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), U2(ForegroundColor) or U2(BackgroundColor) shl 4);
    try
      WriteLine(Text);
    finally
      SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), U2(ccLightGray)); // Default
    end;
end;

end.
