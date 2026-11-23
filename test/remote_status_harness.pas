program remote_status_harness;

{$mode delphi}
{$codepage utf8}

uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, URemoteStatus;

var
  Bridge: TRemoteStatus;
  Command: string;
begin
  Bridge := TRemoteStatus.Create(StrToInt(ParamStr(1)));
  Bridge.Start;
  try
    while not EOF do
    begin
      ReadLn(Command);
      if Command = 'start' then
        Bridge.Started('Björk', 'A "song"', '/songs/ä.txt')
      else if Command = 'pause' then
        Bridge.Paused(True)
      else if Command = 'resume' then
        Bridge.Paused(False)
      else if Command = 'stop' then
        Bridge.Stopped
      else if Command = 'exit' then
        Break;
    end;
  finally
    Bridge.Free;
  end;
end.
