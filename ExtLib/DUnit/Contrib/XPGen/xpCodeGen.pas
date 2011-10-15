unit xpCodeGen;
(*
 * The contents of this file are subject to the Mozilla Public
 * License Version 1.1 (the "License"); you may not use this file
 * except in compliance with the License. You may obtain a copy of
 * the License at http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS
 * IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * rights and limitations under the License.
 *
 * This code was inspired to expidite the creation of unit tests
 * for use the Dunit test frame work.
 *
 * The Initial Developer of XPGen is Michael A. Johnson.
 * Portions created The Initial Developer is Copyright (C) 2000.
 * Portions created by The DUnit Group are Copyright (C) 2000.
 * All rights reserved.
 *
 * Contributor(s):
 * Michael A. Johnson <majohnson@golden.net>
 * Juanco A�ez <juanco@users.sourceforge.net>
 * Chris Morris <chrismo@users.sourceforge.net>
 * Jeff Moore <JeffMoore@users.sourceforge.net>
 * The DUnit group at SourceForge <http://dunit.sourceforge.net>
 *
 *)
{
Unit        : xpCodeGen

Description : This unit is responsible for generating output code from a sequence
              of parse nodes generated by the parser

Programmer  : mike

Date        : 06-Jul-2000
}

interface
uses
  classes,
  ParseDef,
  xpParse;
type

  DriverSrcOutput = class
  public
    procedure OutputStart(NameOfUnit: string); virtual; abstract;
    procedure OutputSrcCode(srcLine: string); virtual; abstract;
    procedure OutputFinish; virtual; abstract;
  end;

  DriverSrcOutputTstrings = class(DriverSrcOutput)
    fOutputStrings: TStrings;
  public
    constructor Create(newtarget: TStrings);
    destructor Destroy; override;
    procedure OutputStart(NameOfUnit: string); override;
    procedure OutputSrcCode(srcLine: string); override;
    procedure OutputFinish; override;
  end;

  DriverSrcOutputText = class(DriverSrcOutputTstrings)
  protected
    SourceCodeBuffer: TStringList;
  public
    constructor Create;
    destructor Destroy; override;
    function Text: string;
  end;

  SrcGenExternalTest = class
  protected
    fNameOfUnit: string;
    ftestMethodPrefix: string;
    fTestUnitPrefix: string;
    fTestClassPrefix: string;
    fOutputDriver: DriverSrcOutput;
  public
    constructor Create(newUnitName: string; driver: DriverSrcOutput);
    destructor Destroy; override;
    procedure GenerateCode(ParseNodeList: TList); virtual;
  end;

implementation

uses
  SysUtils;

{ DriverSrcOutputTstrings }

constructor DriverSrcOutputTstrings.Create(newtarget: TStrings);
begin
  inherited Create;
  fOutputStrings := newtarget;
end;

destructor DriverSrcOutputTstrings.Destroy;
begin
  inherited Destroy;
end;

procedure DriverSrcOutputTstrings.OutputFinish;
begin
  { it's necessary to provide an implementation because of the pure virtual designation }
end;

procedure DriverSrcOutputTstrings.OutputSrcCode(srcLine: string);
begin
  foutputStrings.Add(srcLine);
end;

procedure DriverSrcOutputTstrings.OutputStart(NameOfUnit: string);
begin
  { it's necessary to provide an implementation because of the pure virtual designation }
  foutputStrings.clear;
end;

{ SrcGenExternalTest }

constructor SrcGenExternalTest.Create(newUnitName: string; driver:
  DriverSrcOutput);
begin

  ftestMethodPrefix := 'Verify';
  fTestUnitPrefix := 'Test_';
  fTestClassPrefix := 'Check_';

  fNameOfUnit := newUnitName;
  fOutputDriver := driver;
  inherited Create;
end;

destructor SrcGenExternalTest.Destroy;
begin
  inherited Destroy;
end;

procedure SrcGenExternalTest.GenerateCode(ParseNodeList: TList);
{
Procedure   : SrcGenExternalTest.GenerateCode

Description : generates output based on the parsednodes found in the parse step

Input       : ParseNodeList: TList

Programmer  : mike

Date        : 07-Jul-2000
}
var
  methodIter,
    NodeIter: integer;
  parseNode: TParseNodeClass;
begin
  if assigned(foutputDriver) then
    begin
      with foutputDriver do
        begin
          OutputStart(fNameOfUnit);
          OutputSrcCode('unit ' + fTestUnitPrefix + fNameOfUnit + ';');
          OutputSrcCode('');
          OutputSrcCode('interface');
          OutputSrcCode('');
          OutputSrcCode('uses');
          OutputSrcCode('  ' + 'TestFramework' + ',');
          OutputSrcCode('  ' + 'SysUtils' + ',');
          OutputSrcCode('  ' + fNameOfUnit + ';');
          OutputSrcCode('');
          OutputSrcCode('type');
          { generate crack classes for accessing protected methods }
          for nodeIter := 0 to ParseNodeList.count - 1 do
            begin
              ParseNode := ParseNodeList[nodeIter];
              if (ParseNode.PubMethodList.count > 0) or
                (ParseNode.PrtMethodList.count > 0) then
                begin
                  OutputSrcCode('');
                  OutputSrcCode('CRACK_' + ParseNode.NameClass + ' = class(' +
                    ParseNode.NameClass + ');');
                end;
            end;

          for nodeIter := 0 to ParseNodeList.count - 1 do
            begin
              ParseNode := ParseNodeList[nodeIter];
              if (ParseNode.PubMethodList.count > 0) or
                (ParseNode.PrtMethodList.count > 0) then
                begin
                  OutputSrcCode('');
                  OutputSrcCode(fTestClassPrefix + ParseNode.NameClass +
                    ' = class(TTestCase)');
                  OutputSrcCode('public');
                  OutputSrcCode('   procedure setUp;  override;');
                  OutputSrcCode('   procedure tearDown; override;');
                  OutputSrcCode('published');
                  { test the public/published/automated methods }
                  for methodIter := 0 to ParseNode.PubMethodList.count - 1 do
                    begin
                      OutputSrcCode('   procedure ' + ftestMethodPrefix +
                        ParseNode.PubMethodList[methodIter] + ';');
                    end;
                  { test the protected methods too }
                  for methodIter := 0 to ParseNode.PrtMethodList.count - 1 do
                    begin
                      OutputSrcCode('   procedure ' + ftestMethodPrefix +
                        ParseNode.PrtMethodList[methodIter] + ';');
                    end;
                  OutputSrcCode('end;');
                end;
            end;
          OutputSrcCode('');
          OutputSrcCode('function Suite : ITestSuite;');
          OutputSrcCode('');
          OutputSrcCode('implementation');
          OutputSrcCode('');

          { write the implemention for the test suite }
          OutputSrcCode('function Suite : ITestSuite;');
          OutputSrcCode('begin');
          outputSrcCode('  result := TTestSuite.Create(''' + fNameOfUnit +
            ' Tests'');');
          { add each test method to the suite for this unit }
          for nodeIter := 0 to ParseNodeList.count - 1 do
            begin
              ParseNode := ParseNodeList[nodeIter];
              if (ParseNode.PubMethodList.count > 0) or
                (ParseNode.PrtMethodList.count > 0) then
                begin
                  OutputSrcCode('');
                  OutputSrcCode(format('  result.addTest(testSuiteOf(%s%s));',
                    [fTestClassPrefix, ParseNode.NameClass]));
                end;
            end;
          OutputSrcCode('end;');

          { write the implementation for each of the test classes }
          for nodeIter := 0 to ParseNodeList.count - 1 do
            begin
              ParseNode := ParseNodeList[nodeIter];
              if (ParseNode.PubMethodList.count > 0) or
                (ParseNode.PrtMethodList.count > 0) then
                begin
                  OutputSrcCode('');
                  OutputSrcCode('procedure ' + fTestClassPrefix +
                    ParseNode.NameClass + '.setUp;');
                  OutputSrcCode('begin');
                  OutputSrcCode('end;');
                  OutputSrcCode('');
                  OutputSrcCode('procedure ' + fTestClassPrefix +
                    ParseNode.NameClass + '.tearDown;');
                  OutputSrcCode('begin');
                  OutputSrcCode('end;');
                  { generate public,automated and published methods }
                  for methodIter := 0 to ParseNode.PubMethodList.count - 1 do
                    begin
                      OutputSrcCode('');
                      OutputSrcCode('procedure ' + fTestClassPrefix +
                        ParseNode.NameClass + '.' + fTestMethodPrefix +
                        ParseNode.PubMethodList[methodIter] + ';');
                      OutputSrcCode('begin');
                      OutputSrcCode('   fail(''Test Not Implemented Yet'');');
                      OutputSrcCode('end;');
                    end;
                  { generate for the protected ones too }
                  for methodIter := 0 to ParseNode.PrtMethodList.count - 1 do
                    begin
                      OutputSrcCode('');
                      OutputSrcCode('procedure ' + fTestClassPrefix +
                        ParseNode.NameClass + '.' + fTestMethodPrefix +
                        ParseNode.PrtMethodList[methodIter] + ';');
                      OutputSrcCode('begin');
                      OutputSrcCode('   fail(''Test Not Implemented Yet'');');
                      OutputSrcCode('end;');
                    end;
                end;
            end;
          OutputSrcCode('');
          OutputSrcCode('end.');
          OutputFinish;
        end;
    end;
end;

{ DriverSrcOutputText }

constructor DriverSrcOutputText.Create;
begin
  { create a stub where this data can be held }
  SourceCodeBuffer := TStringList.Create;
  inherited create(SourceCodeBuffer);
end;

destructor DriverSrcOutputText.Destroy;
begin
  SourceCodeBuffer.Free;
  inherited Destroy;
end;

function DriverSrcOutputText.Text: string;
var
  sourceLineIter: integer;
begin
  result := '';
  { generate text when there is something to output }
  if SourceCodeBuffer.Count > 0 then
    begin
      result := SourceCodeBuffer[0];
      { output any other text that we need }
      for sourceLineIter := 1 to SourceCodeBuffer.Count - 1 do
        begin
          result := result + #13 + SourceCodeBuffer[sourceLineIter];
        end;
    end;
end;

end.

